import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../services/local_db.dart';
import '../../services/sensor_service.dart';

/// Mini game "Tilt Catch" (gaya Pou): miringkan HP ke kiri/kanan seperti setir untuk menggeser karakter
/// dan menangkap konfeti yang jatuh. Hindari bom! 60 detik, 3 nyawa.
///
/// Sensor: GYROSCOPE (kecepatan putar sumbu Z) diintegralkan menjadi sudut miring, lalu dikoreksi pelan
/// oleh accelerometer (filter komplementer) supaya tidak drift.
/// Kontrol HANYA lewat sensor: menggeser layar dengan jari tidak menggerakkan karakter.
/// HP tanpa gyroscope tidak bisa memainkan game ini (tombol Start dinonaktifkan dengan keterangan).
class TiltGamePage extends StatefulWidget {
  const TiltGamePage({super.key});

  /// Kunci pengaturan di tabel app_settings.
  static const String bestKey = 'tilt_best';
  static const String invertKey = 'tilt_invert';

  static const int roundSeconds = 60;
  static const int startLives = 3;

  @override
  State<TiltGamePage> createState() => _TiltGamePageState();
}

enum _Phase { ready, playing, paused, over }

class _Item {
  _Item(this.kind, this.x, this.y, this.speed);
  final int kind; // 0 konfeti, 1 nada, 2 bintang, 3 bom
  final double x;
  double y;
  final double speed; // piksel per detik
}

class _Pop {
  _Pop(this.x, this.y, this.text, this.color);
  final double x;
  final double y;
  final String text;
  final Color color;
  double age = 0;
}

double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

class _TiltGamePageState extends State<TiltGamePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ---- ukuran & penampilan ----
  static const double _floor = 34; // tinggi lantai panggung
  static const double _bodyW = 84;
  static const double _bodyH = 74;

  // ---- kontrol miring ----
  static const double _deadZone = 0.05; // rad (~3°) diabaikan
  static const double _fullTilt = 0.42; // rad (~24°) = kecepatan maksimum
  static const double _accTau = 0.6; // detik: seberapa cepat accelerometer mengoreksi drift gyroscope

  /// Jenis item: emoji, poin.
  static const List<String> _emojiChars = <String>['\u{1F389}', '\u{1F3B5}', '⭐', '\u{1F4A3}'];
  static const List<int> _points = <int>[1, 2, 5, 0];

  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final math.Random _rng = math.Random();
  late final List<TextPainter> _emoji;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  Timer? _gyroWatch; // menunggu event gyroscope pertama
  bool _gyroSeen = false;
  bool _noGyro = false; // tidak ada data gyroscope -> game tidak bisa dimainkan
  final Stopwatch _clock = Stopwatch()..start();
  int? _lastGyroUs;
  int? _lastAccUs;
  Duration? _lastTick;

  // sudut miring ke KANAN (rad), hasil gabungan gyroscope + accelerometer
  double _phi = 0;
  bool _phiReady = false;
  double _offset = 0; // posisi netral (diambil saat Start / Recenter)
  bool _invert = false;

  Size _size = Size.zero;
  double _px = -1; // posisi x karakter
  double _vel = 0;
  double _ctrl = 0; // -1..1, untuk mata, kemiringan badan, dan indikator

  final List<_Item> _items = <_Item>[];
  final List<_Pop> _pops = <_Pop>[];
  _Phase _phase = _Phase.ready;
  int _score = 0;
  int _lives = TiltGamePage.startLives;
  int _combo = 0;
  double _timeLeft = TiltGamePage.roundSeconds.toDouble();
  double _playTime = 0;
  double _spawnIn = 0.6;
  double _mouth = 0;
  double _hurt = 0;
  int? _best;
  bool _newBest = false;

  // nilai yang sedang tampil di HUD (setState hanya bila berubah, bukan tiap frame)
  int _shownScore = -1;
  int _shownLives = -1;
  int _shownSecs = -1;
  int _shownMult = -1;

  int get _mult => 1 + math.min(_combo ~/ 5, 3);

  double get _tilt => (_invert ? -1 : 1) * _wrap(_phi - _offset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // putar-layar-dengan-gyroscope (milik halaman lain) dimatikan selama game, supaya layar tidak tiba-tiba landscape
    SensorService.instance.twistEnabled = false;

    _emoji = <TextPainter>[
      for (final e in _emojiChars)
        TextPainter(text: TextSpan(text: e, style: const TextStyle(fontSize: 34)), textDirection: TextDirection.ltr)
          ..layout(),
    ];

    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      _onGyro,
      onError: (Object _) => _setNoGyro(),
    );
    // gyroscope yang ada selalu mengirim data terus-menerus; bila 2 detik tidak ada sama sekali, anggap tidak tersedia
    _gyroWatch = Timer(const Duration(seconds: 2), () {
      if (!_gyroSeen) _setNoGyro();
    });
    _accSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      _onAccel,
      onError: (Object _) {/* tanpa accelerometer: gyroscope saja */},
    );
    _ticker.start();
    _loadSaved();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SensorService.instance.twistEnabled = true;
    _gyroWatch?.cancel();
    _gyroSub?.cancel();
    _accSub?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) _pause();
  }

  Future<void> _loadSaved() async {
    try {
      final uid = currentUserId();
      final best = await LocalDb.instance.getInt(uid, TiltGamePage.bestKey);
      final invert = await LocalDb.instance.getBool(uid, TiltGamePage.invertKey);
      if (mounted) {
        setState(() {
          _best = best;
          _invert = invert;
        });
      }
    } catch (_) {/* abaikan */}
  }

  // ---------------- Sensor ----------------

  void _setNoGyro() {
    if (!mounted || _gyroSeen || _noGyro) return;
    setState(() => _noGyro = true);
  }

  void _onGyro(GyroscopeEvent e) {
    if (!_gyroSeen) {
      _gyroSeen = true;
      if (_noGyro && mounted) setState(() => _noGyro = false);
    }
    final us = _clock.elapsedMicroseconds;
    final last = _lastGyroUs;
    _lastGyroUs = us;
    if (last == null) return;
    final dt = _clampD((us - last) / 1e6, 0, 0.1);
    // Z positif = berputar berlawanan arah jarum jam = miring ke KIRI, jadi sudut "miring kanan" berkurang.
    _phi -= e.z * dt;
  }

  void _onAccel(AccelerometerEvent e) {
    final us = _clock.elapsedMicroseconds;
    final last = _lastAccUs;
    _lastAccUs = us;

    final inPlane = math.sqrt(e.x * e.x + e.y * e.y);
    final norm = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    // HP terlalu rata (gravitasi nyaris tegak lurus layar) atau sedang diguncang: sudut dari accelerometer tidak bisa dipercaya
    if (inPlane < 3.0 || (norm - 9.81).abs() > 2.0) return;

    // HP tegak diam membaca (x=0, y=+9.8); miring searah jarum jam (ke kanan) membuat x negatif.
    final acc = math.atan2(-e.x, e.y);
    if (!_phiReady) {
      _phi = acc;
      _phiReady = true;
      return;
    }
    if (last == null) return;
    final dt = _clampD((us - last) / 1e6, 0, 0.1);
    _phi += _wrap(acc - _phi) * math.min(1.0, dt / _accTau);
  }

  // ---------------- Loop game ----------------

  void _onTick(Duration elapsed) {
    final prev = _lastTick;
    _lastTick = elapsed;
    final dt = prev == null ? 0.0 : _clampD((elapsed - prev).inMicroseconds / 1e6, 0, 0.05);
    if (_phase == _Phase.ready) {
      _movePlayer(dt); // pratinjau: karakter sudah bisa digerakkan sebelum Start
    } else if (_phase == _Phase.playing) {
      _step(dt);
    }
    _repaint.value++;
  }

  void _movePlayer(double dt) {
    final w = _size.width;
    if (w <= 0) return;
    final t = _tilt;
    var s = 0.0;
    if (t.abs() > _deadZone) {
      s = _clampD((t.abs() - _deadZone) / (_fullTilt - _deadZone), 0, 1) * (t < 0 ? -1 : 1);
    }
    _ctrl = s;
    final maxSpeed = w * 1.5;
    _vel += (s * maxSpeed - _vel) * math.min(1.0, 12 * dt);
    _px = _clampD(_px + _vel * dt, _bodyW / 2, w - _bodyW / 2);
  }

  void _step(double dt) {
    _movePlayer(dt);
    _playTime += dt;
    _timeLeft -= dt;
    _mouth = math.max(0, _mouth - dt);
    _hurt = math.max(0, _hurt - dt);
    if (_timeLeft <= 0) {
      _timeLeft = 0;
      unawaited(_finish());
      return;
    }

    final p = _clampD(_playTime / TiltGamePage.roundSeconds, 0, 1); // 0..1: makin sulit
    _spawnIn -= dt;
    if (_spawnIn <= 0) {
      _spawn(p);
      _spawnIn = (0.85 - 0.47 * p) * (0.8 + _rng.nextDouble() * 0.4);
    }

    final h = _size.height;
    final playerTop = h - _floor - _bodyH;
    var dead = false;
    _items.removeWhere((it) {
      it.y += it.speed * dt;
      final caught = it.y + 14 >= playerTop && it.y <= playerTop + 44 && (it.x - _px).abs() < _bodyW / 2 + 6;
      if (caught) {
        if (_onCatch(it)) dead = true;
        return true;
      }
      if (it.y > h + 24) {
        if (it.kind != 3) _combo = 0; // melewatkan item bagus memutus combo
        return true;
      }
      return false;
    });
    for (final pop in _pops) {
      pop.age += dt;
    }
    _pops.removeWhere((pop) => pop.age > 0.8);

    if (dead) {
      unawaited(_finish());
      return;
    }
    _syncHud();
  }

  void _spawn(double p) {
    final w = _size.width;
    if (w <= 0) return;
    final r = _rng.nextDouble();
    final bomb = 0.18 + 0.14 * p;
    final star = 0.07;
    final note = 0.25;
    final kind = r < bomb ? 3 : (r < bomb + star ? 2 : (r < bomb + star + note ? 1 : 0));
    final x = 24 + _rng.nextDouble() * (w - 48);
    final speed = _size.height * (0.32 + 0.38 * p) * (0.9 + _rng.nextDouble() * 0.2);
    _items.add(_Item(kind, x, -20, speed));
  }

  /// Mengembalikan true jika game berakhir (nyawa habis).
  bool _onCatch(_Item it) {
    final y = _size.height - _floor - _bodyH;
    if (it.kind == 3) {
      _lives--;
      _combo = 0;
      _hurt = 0.4;
      _pops.add(_Pop(it.x, y, '-1', AppColors.danger));
      HapticFeedback.heavyImpact();
      return _lives <= 0;
    }
    _combo++;
    final gain = _points[it.kind] * _mult;
    _score += gain;
    _mouth = 0.25;
    _pops.add(_Pop(it.x, y, '+$gain', AppColors.sun));
    HapticFeedback.selectionClick();
    return false;
  }

  void _syncHud() {
    final secs = _timeLeft.ceil();
    final mult = _mult;
    if (secs != _shownSecs || _score != _shownScore || _lives != _shownLives || mult != _shownMult) {
      _shownSecs = secs;
      _shownScore = _score;
      _shownLives = _lives;
      _shownMult = mult;
      if (mounted) setState(() {});
    }
  }

  // ---------------- Kontrol game ----------------

  void _start() {
    setState(() {
      _items.clear();
      _pops.clear();
      _score = 0;
      _lives = TiltGamePage.startLives;
      _combo = 0;
      _timeLeft = TiltGamePage.roundSeconds.toDouble();
      _playTime = 0;
      _spawnIn = 0.6;
      _mouth = 0;
      _hurt = 0;
      _vel = 0;
      _newBest = false;
      _offset = _phi; // posisi HP saat ini dianggap netral
      _shownScore = _shownLives = _shownSecs = _shownMult = -1;
      _phase = _Phase.playing;
    });
  }

  void _pause() {
    if (_phase != _Phase.playing) return;
    setState(() => _phase = _Phase.paused);
  }

  void _resume() {
    if (_phase != _Phase.paused) return;
    setState(() {
      _offset = _phi; // pegangan HP mungkin berubah selama jeda
      _phase = _Phase.playing;
    });
  }

  void _recenter() {
    _offset = _phi;
    _vel = 0;
    _snack('Centered. Your current position is now neutral.');
  }

  Future<void> _toggleInvert() async {
    setState(() => _invert = !_invert);
    _snack(_invert ? 'Tilt direction flipped.' : 'Tilt direction back to normal.');
    try {
      await LocalDb.instance.setBool(currentUserId(), TiltGamePage.invertKey, _invert);
    } catch (_) {/* abaikan */}
  }

  Future<void> _finish() async {
    if (_phase == _Phase.over) return;
    _phase = _Phase.over;
    HapticFeedback.mediumImpact();
    if (mounted) setState(() {});
    try {
      final uid = currentUserId();
      final previous = await LocalDb.instance.getInt(uid, TiltGamePage.bestKey);
      final isBest = _score > 0 && (previous == null || _score > previous);
      if (isBest) await LocalDb.instance.setInt(uid, TiltGamePage.bestKey, _score);
      if (mounted) {
        setState(() {
          _newBest = isBest;
          _best = isBest ? _score : previous;
        });
      }
    } catch (_) {/* skor tidak tersimpan */}
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1400)));
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tilt Catch'),
        actions: <Widget>[
          IconButton(tooltip: 'Recenter', icon: const Icon(Icons.center_focus_strong_outlined), onPressed: _recenter),
          IconButton(tooltip: 'Flip tilt direction', icon: const Icon(Icons.swap_horiz), onPressed: _toggleInvert),
          if (_phase == _Phase.playing)
            IconButton(tooltip: 'Pause', icon: const Icon(Icons.pause_circle_outline), onPressed: _pause),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        _size = Size(c.maxWidth, c.maxHeight);
        _px = _px < 0 ? _size.width / 2 : _clampD(_px, _bodyW / 2, math.max(_bodyW / 2, _size.width - _bodyW / 2));
        // Sengaja tanpa GestureDetector: karakter hanya bergerak lewat kemiringan HP (gyroscope).
        return Stack(children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: _TiltPainter(this))),
          if (_phase == _Phase.playing || _phase == _Phase.paused) _hud(),
          if (_phase == _Phase.ready) _overlay(_readyCard()),
          if (_phase == _Phase.paused) _overlay(_pausedCard()),
          if (_phase == _Phase.over) _overlay(_overCard()),
        ]);
      }),
    );
  }

  Widget _hud() {
    final secs = _timeLeft.ceil();
    return Positioned(
      left: 12,
      right: 12,
      top: 8,
      child: IgnorePointer(
        child: Row(children: <Widget>[
          Row(children: <Widget>[
            for (var i = 0; i < TiltGamePage.startLives; i++)
              Icon(i < _lives ? Icons.favorite : Icons.favorite_border, color: AppColors.danger, size: 24),
          ]),
          const Spacer(),
          Tag('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}', icon: Icons.timer_outlined),
          const Spacer(),
          if (_mult > 1) ...<Widget>[Tag('x$_mult combo'), const SizedBox(width: 8)],
          Text('$_score', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.sun)),
        ]),
      ),
    );
  }

  Widget _overlay(Widget card) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xB30A192F),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(child: card),
      ),
    );
  }

  Widget _readyCard() {
    return AppCard(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Icon(Icons.screen_rotation_alt_rounded, size: 48, color: AppColors.sun),
        const SizedBox(height: 8),
        Text('Tilt Catch',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Hold your phone upright and tilt it left or right like a steering wheel to move. '
          'The screen cannot be dragged: only the gyroscope controls the game.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.sky, height: 1.4),
        ),
        const SizedBox(height: 12),
        const Text(
          '\u{1F389} +1    \u{1F3B5} +2    ⭐ +5    \u{1F4A3} -1 life',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          '60 seconds, 3 lives. Catch 5 in a row for a combo bonus.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.skyDim, fontSize: 12.5),
        ),
        if (_best != null) ...<Widget>[const SizedBox(height: 10), Tag('Best: $_best pts')],
        const SizedBox(height: 16),
        if (_noGyro) ...<Widget>[
          const Text(
            'No gyroscope data detected. This game needs a phone with a gyroscope (emulators usually do not have one).',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.danger, fontSize: 12.5, height: 1.3),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _noGyro ? null : _start, child: const Text('Start')),
        ),
        const SizedBox(height: 6),
        const Text(
          'Moving the wrong way? Use the ⇄ button at the top.',
          style: TextStyle(color: AppColors.skyDim, fontSize: 11.5),
        ),
      ]),
    );
  }

  Widget _pausedCard() {
    return AppCard(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text('Paused', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _resume, child: const Text('Resume'))),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Quit')),
        ),
      ]),
    );
  }

  Widget _overCard() {
    final timeUp = _lives > 0;
    return AppCard(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(timeUp ? Icons.emoji_events_rounded : Icons.heart_broken, size: 56, color: AppColors.sun),
        const SizedBox(height: 6),
        Text(timeUp ? "Time's up!" : 'Out of lives!',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('$_score', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const Text('points', style: TextStyle(color: AppColors.sky)),
        const SizedBox(height: 10),
        if (_newBest) const Tag('New best!', icon: Icons.star_rounded) else if (_best != null) Tag('Best: $_best pts'),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _start, child: const Text('Play again'))),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        ),
      ]),
    );
  }
}

/// Menggambar panggung, item, karakter, dan indikator kemiringan. Dipicu ulang tiap frame lewat [repaint].
class _TiltPainter extends CustomPainter {
  _TiltPainter(this.g) : super(repaint: g._repaint);
  final _TiltGamePageState g;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const floor = _TiltGamePageState._floor;
    const bodyW = _TiltGamePageState._bodyW;
    const bodyH = _TiltGamePageState._bodyH;

    // latar + sorotan lampu panggung
    final full = Offset.zero & size;
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.bg, AppColors.bgAlt],
        ).createShader(full),
    );
    final beam = Paint()..color = const Color(0x12FFD444);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.18, 0)
        ..lineTo(w * 0.02, h)
        ..lineTo(w * 0.50, h)
        ..close(),
      beam,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.82, 0)
        ..lineTo(w * 0.50, h)
        ..lineTo(w * 0.98, h)
        ..close(),
      beam,
    );

    // lantai panggung + indikator kemiringan (berguna untuk melihat sensor bekerja)
    canvas.drawRect(Rect.fromLTWH(0, h - floor, w, floor), Paint()..color = AppColors.primary);
    canvas.drawLine(
      Offset(0, h - floor),
      Offset(w, h - floor),
      Paint()
        ..color = AppColors.sky
        ..strokeWidth = 2,
    );
    final my = h - floor / 2;
    final track = Paint()
      ..color = AppColors.skyFaint
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w / 2 - 70, my), Offset(w / 2 + 70, my), track);
    canvas.drawLine(Offset(w / 2, my - 6), Offset(w / 2, my + 6), Paint()..color = AppColors.sky);
    canvas.drawCircle(Offset(w / 2 + g._ctrl * 70, my), 7, Paint()..color = AppColors.sun);

    // item jatuh
    for (final it in g._items) {
      if (it.kind == 3) {
        canvas.drawCircle(Offset(it.x, it.y), 24, Paint()..color = const Color(0x33FF4D4D));
      }
      final tp = g._emoji[it.kind];
      tp.paint(canvas, Offset(it.x - tp.width / 2, it.y - tp.height / 2));
    }

    // karakter
    final baseY = h - floor;
    canvas.save();
    canvas.translate(g._px, baseY);
    canvas.rotate(g._ctrl * 0.2); // badan ikut miring seperti Pou
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(-bodyW / 2, -bodyH, bodyW, bodyH), const Radius.circular(34));
    canvas.drawRRect(body, Paint()..color = AppColors.sun);
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFFE0B21C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // pipi
    final cheek = Paint()..color = const Color(0x66FF6B6B);
    canvas.drawCircle(const Offset(-29, -28), 6, cheek);
    canvas.drawCircle(const Offset(29, -28), 6, cheek);
    // mata mengikuti arah miring
    final white = Paint()..color = Colors.white;
    final pupil = Paint()..color = AppColors.ink;
    for (final ex in const <double>[-17, 17]) {
      canvas.drawCircle(Offset(ex, -48), 9, white);
      canvas.drawCircle(Offset(ex + g._ctrl * 3.5, -47), 4.5, pupil);
    }
    // mulut: terbuka saat menangkap, senyum saat biasa
    if (g._mouth > 0) {
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, -30), width: 26, height: 20), pupil);
    } else {
      canvas.drawArc(
        Rect.fromCenter(center: const Offset(0, -34), width: 24, height: 14),
        0.15,
        math.pi - 0.3,
        false,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();

    // teks poin melayang
    for (final p in g._pops) {
      final a = _clampD(1 - p.age / 0.8, 0, 1);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(color: p.color.withValues(alpha: a), fontSize: 22, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.x - tp.width / 2, p.y - 20 - p.age * 60));
    }

    // kilatan merah saat kena bom
    if (g._hurt > 0) {
      canvas.drawRect(full, Paint()..color = Color.fromRGBO(255, 60, 60, math.min(0.35, g._hurt)));
    }
  }

  @override
  bool shouldRepaint(covariant _TiltPainter oldDelegate) => true;
}
