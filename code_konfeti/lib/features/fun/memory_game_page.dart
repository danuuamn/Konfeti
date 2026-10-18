import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../services/local_db.dart';

/// Mini game "Concert Memory": cocokkan 8 pasang ikon. Tidak butuh internet atau API apa pun.
class MemoryGamePage extends StatefulWidget {
  const MemoryGamePage({super.key});

  /// Kunci skor terbaik (jumlah langkah paling sedikit) di tabel app_settings.
  static const String bestKey = 'memory_best_moves';

  @override
  State<MemoryGamePage> createState() => _MemoryGamePageState();
}

class _MemoryGamePageState extends State<MemoryGamePage> {
  static const List<IconData> _icons = <IconData>[
    Icons.music_note,
    Icons.mic,
    Icons.headphones,
    Icons.queue_music,
    Icons.piano,
    Icons.speaker,
    Icons.star,
    Icons.celebration,
  ];

  late List<int> _cards;
  final Set<int> _faceUp = <int>{}; // kartu terbuka yang belum cocok
  final Set<int> _matched = <int>{};
  int? _first;
  bool _lock = false;
  int _moves = 0;
  int _seconds = 0;
  int? _best;
  Timer? _timer;

  bool get _won => _matched.length == _cards.length;

  @override
  void initState() {
    super.initState();
    _newGame();
    _loadBest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newGame() {
    _timer?.cancel();
    _timer = null;
    _cards = <int>[
      for (var i = 0; i < _icons.length; i++) ...<int>[i, i],
    ]..shuffle();
    _faceUp.clear();
    _matched.clear();
    _first = null;
    _lock = false;
    _moves = 0;
    _seconds = 0;
  }

  Future<void> _loadBest() async {
    try {
      final best = await LocalDb.instance.getInt(currentUserId(), MemoryGamePage.bestKey);
      if (mounted) setState(() => _best = best);
    } catch (_) {/* abaikan */}
  }

  void _tap(int i) {
    if (_lock || _won || _faceUp.contains(i) || _matched.contains(i)) return;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    setState(() => _faceUp.add(i));

    final first = _first;
    if (first == null) {
      _first = i;
      return;
    }
    _first = null;
    setState(() => _moves++);

    if (_cards[first] == _cards[i]) {
      setState(() {
        _matched.add(first);
        _matched.add(i);
        _faceUp.remove(first);
        _faceUp.remove(i);
      });
      if (_won) _finish();
    } else {
      _lock = true; // beri waktu melihat kedua kartu sebelum ditutup lagi
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _faceUp.remove(first);
          _faceUp.remove(i);
          _lock = false;
        });
      });
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _timer = null;
    try {
      final uid = currentUserId();
      final previous = await LocalDb.instance.getInt(uid, MemoryGamePage.bestKey);
      if (previous == null || _moves < previous) {
        await LocalDb.instance.setInt(uid, MemoryGamePage.bestKey, _moves);
        if (mounted) setState(() => _best = _moves);
      } else if (mounted) {
        setState(() => _best = previous);
      }
    } catch (_) {/* skor tidak tersimpan */}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Concert Memory'), actions: const <Widget>[RotateButton()]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: <Widget>[
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[
              _stat(Icons.touch_app_outlined, 'Moves', '$_moves'),
              _stat(Icons.timer_outlined, 'Time', '${_seconds}s'),
              _stat(Icons.emoji_events_outlined, 'Best', _best == null ? '-' : '$_best'),
            ]),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: <Widget>[for (var i = 0; i < _cards.length; i++) _card(i)],
            ),
          ),
          const SizedBox(height: 12),
          if (_won)
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Text(
                'You did it in $_moves moves and ${_seconds}s!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: _won
                ? FilledButton(onPressed: () => setState(_newGame), child: const Text('Play again'))
                : OutlinedButton(onPressed: () => setState(_newGame), child: const Text('Restart')),
          ),
        ]),
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(icon, color: AppColors.sun),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      Text(label, style: const TextStyle(color: AppColors.sky, fontSize: 11)),
    ]);
  }

  Widget _card(int i) {
    final matched = _matched.contains(i);
    final up = matched || _faceUp.contains(i);
    return GestureDetector(
      onTap: () => _tap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: matched ? const Color(0xFF1E7A46) : (up ? AppColors.sun : AppColors.primary),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.skyFaint),
        ),
        child: Center(
          child: up
              ? Icon(_icons[_cards[i]], size: 32, color: matched ? Colors.white : AppColors.ink)
              : const Icon(Icons.help_outline, color: AppColors.sky),
        ),
      ),
    );
  }
}
