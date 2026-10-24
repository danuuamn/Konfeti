import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';

/// Pengenal lagu ala Shazam: rekam suara sekitar beberapa detik, kirim ke backend (/api/recognize, AudD),
/// lalu tampilkan judul, artis, album, dan tautan Spotify / Apple Music.
class SongRecognizerPage extends StatefulWidget {
  const SongRecognizerPage({super.key});

  @override
  State<SongRecognizerPage> createState() => _SongRecognizerPageState();
}

enum _Stage { idle, listening, analyzing, found, notFound, failed }

class _SongRecognizerPageState extends State<SongRecognizerPage> with SingleTickerProviderStateMixin {
  static const int _maxSeconds = 12; // otomatis berhenti
  static const int _minSeconds = 4; // terlalu pendek -> sulit dikenali

  final AudioRecorder _rec = AudioRecorder();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  Timer? _timer;
  _Stage _stage = _Stage.idle;
  int _elapsed = 0;
  String? _error;
  Map<String, dynamic>? _song;
  String? _path;

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _rec.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    _timer?.cancel();
    _pulse.stop();
    setState(() {
      _stage = _Stage.failed;
      _error = message;
    });
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        _fail('Microphone permission is needed to listen to a song. Allow it in your phone settings and try again.');
        return;
      }
      final path = '${Directory.systemTemp.path}${Platform.pathSeparator}konfeti_listen_'
          '${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(), path: path);
      _path = path;
      if (!mounted) return;
      setState(() {
        _stage = _Stage.listening;
        _elapsed = 0;
        _error = null;
        _song = null;
      });
      _pulse.repeat(reverse: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= _maxSeconds) _finish();
      });
    } catch (e) {
      _fail('Could not start recording: $e');
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    _pulse.stop();
    try {
      await _rec.stop();
    } catch (_) {/* abaikan */}
    await _deleteTemp();
    if (mounted) setState(() => _stage = _Stage.idle);
  }

  Future<void> _deleteTemp() async {
    final p = _path;
    _path = null;
    if (p == null) return;
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {/* abaikan */}
  }

  Future<void> _finish() async {
    if (_stage != _Stage.listening) return;
    _timer?.cancel();
    _pulse.stop();
    setState(() => _stage = _Stage.analyzing);
    try {
      final stopped = await _rec.stop();
      final path = stopped ?? _path;
      if (path == null) throw ApiException(0, 'No recording was made.');
      final bytes = await File(path).readAsBytes();
      final res = await ApiClient.instance.post('/api/recognize', <String, Object?>{
        'audio': base64Encode(bytes),
        'ext': 'm4a',
      }) as Map;
      if (!mounted) return;
      if (res['found'] == true) {
        setState(() {
          _song = Map<String, dynamic>.from(res);
          _stage = _Stage.found;
        });
      } else {
        setState(() => _stage = _Stage.notFound);
      }
    } catch (e) {
      _fail(e.toString());
    } finally {
      await _deleteTemp();
    }
  }

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack('Could not open the link.');
    } catch (_) {
      if (mounted) _snack('Could not open the link.');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Song Finder')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: <Widget>[
        const SizedBox(height: 12),
        _micButton(),
        const SizedBox(height: 16),
        Text(_headline(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(_hint(),
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sky, height: 1.4)),
        const SizedBox(height: 20),
        if (_stage == _Stage.listening)
          Center(
            child: _elapsed >= _minSeconds
                ? FilledButton.icon(
                    onPressed: _finish, icon: const Icon(Icons.search_rounded), label: const Text('Identify now'))
                : const SizedBox.shrink(),
          ),
        if (_stage == _Stage.listening)
          Center(child: TextButton(onPressed: _cancel, child: const Text('Cancel'))),
        if (_stage == _Stage.analyzing) const Center(child: CircularProgressIndicator()),
        if (_stage == _Stage.found && _song != null) _resultCard(_song!),
        if (_stage == _Stage.notFound || _stage == _Stage.found || _stage == _Stage.failed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Listen again'),
              ),
            ),
          ),
      ]),
    );
  }

  String _headline() {
    switch (_stage) {
      case _Stage.idle:
        return 'What song is this?';
      case _Stage.listening:
        return 'Listening... ${_elapsed}s';
      case _Stage.analyzing:
        return 'Identifying the song...';
      case _Stage.found:
        return 'Found it!';
      case _Stage.notFound:
        return 'No match found';
      case _Stage.failed:
        return 'Something went wrong';
    }
  }

  String _hint() {
    switch (_stage) {
      case _Stage.idle:
        return 'Tap the microphone and hold your phone near the music for $_minSeconds to $_maxSeconds seconds.';
      case _Stage.listening:
        return 'Keep the phone close to the speaker. It stops by itself after $_maxSeconds seconds.';
      case _Stage.analyzing:
        return 'Comparing your recording with millions of songs.';
      case _Stage.found:
        return 'Tap a button to listen to the full song.';
      case _Stage.notFound:
        return 'Try again closer to the speaker, with less background noise. Live or remixed versions can be hard to match.';
      case _Stage.failed:
        return _error ?? 'Please try again.';
    }
  }

  Widget _micButton() {
    final listening = _stage == _Stage.listening;
    final busy = _stage == _Stage.analyzing;
    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = listening ? _pulse.value : 0.0;
          return Stack(alignment: Alignment.center, children: <Widget>[
            Container(
              width: 150 + 50 * t,
              height: 150 + 50 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.sun.withValues(alpha: listening ? 0.18 * (1 - t) + 0.05 : 0.08),
              ),
            ),
            child!,
          ]);
        },
        child: GestureDetector(
          onTap: busy ? null : (listening ? _finish : _start),
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.sun,
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x66FFD444), blurRadius: 28, spreadRadius: -2)],
            ),
            child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, size: 64, color: AppColors.ink),
          ),
        ),
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> s) {
    String? str(String k) {
      final v = s[k]?.toString().trim();
      return (v == null || v.isEmpty || v == 'null') ? null : v;
    }

    final art = str('artwork');
    final album = str('album');
    final date = str('release_date');
    final spotify = str('spotify_url');
    final apple = str('apple_music_url');
    final link = str('song_link');
    return AppCard(
      child: Column(children: <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: art == null
                ? Container(
                    width: 84,
                    height: 84,
                    color: AppColors.primary,
                    child: const Icon(Icons.music_note_rounded, size: 40, color: AppColors.sky),
                  )
                : Image.network(
                    art,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 84,
                      height: 84,
                      color: AppColors.primary,
                      child: const Icon(Icons.music_note_rounded, size: 40, color: AppColors.sky),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(str('title') ?? 'Unknown title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(str('artist') ?? 'Unknown artist',
                  style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w700)),
              if (album != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(album, style: const TextStyle(color: AppColors.sky, fontSize: 12.5)),
              ],
              if (date != null) ...<Widget>[
                const SizedBox(height: 6),
                Tag(date, icon: Icons.event_outlined, outlined: true),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
          if (spotify != null)
            FilledButton.icon(
              onPressed: () => _open(spotify),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Spotify'),
            ),
          if (apple != null)
            OutlinedButton.icon(
              onPressed: () => _open(apple),
              icon: const Icon(Icons.apple),
              label: const Text('Apple Music'),
            ),
          if (spotify == null && apple == null && link != null)
            OutlinedButton.icon(
              onPressed: () => _open(link),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open song page'),
            ),
        ]),
      ]),
    );
  }
}
