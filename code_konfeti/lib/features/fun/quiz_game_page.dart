import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../services/local_db.dart';

/// Mini game "Guess the Artist": soal dibuat backend dari artis di daftar event + data Spotify.
/// preview_url sering kosong (Spotify membatasinya), jadi soal selalu bisa dijawab dari judul lagu + cover album.
class QuizGamePage extends StatefulWidget {
  const QuizGamePage({super.key});

  /// Kunci skor terbaik di tabel app_settings.
  static const String bestKey = 'quiz_best';
  static const int questionCount = 5;

  @override
  State<QuizGamePage> createState() => _QuizGamePageState();
}

class _Question {
  _Question({
    required this.track,
    required this.album,
    required this.image,
    required this.previewUrl,
    required this.options,
    required this.answer,
  });

  final String track;
  final String album;
  final String? image;
  final String? previewUrl;
  final List<String> options;
  final String answer;

  factory _Question.fromJson(Map<String, dynamic> j) => _Question(
        track: (j['track_name'] ?? '').toString(),
        album: (j['album_name'] ?? '').toString(),
        image: j['album_image'] as String?,
        previewUrl: j['preview_url'] as String?,
        options: (j['options'] as List).map((e) => e.toString()).toList(),
        answer: (j['answer'] ?? '').toString(),
      );
}

class _QuizGamePageState extends State<QuizGamePage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _doneSub;

  List<_Question> _questions = <_Question>[];
  bool _loading = true;
  String? _error;
  int _index = 0;
  int _score = 0;
  String? _picked;
  bool _playing = false;
  bool _finished = false;
  int? _best;
  String? _reward;

  @override
  void initState() {
    super.initState();
    _doneSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    _load();
  }

  @override
  void dispose() {
    _doneSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _stopAudio();
    setState(() {
      _loading = true;
      _error = null;
      _finished = false;
      _index = 0;
      _score = 0;
      _picked = null;
      _reward = null;
    });
    try {
      final data = await ApiClient.instance
          .get('/api/spotify/quiz', query: <String, String>{'n': '${QuizGamePage.questionCount}'}) as List;
      final questions = data.map((e) => _Question.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (questions.isEmpty) throw ApiException(0, 'No quiz questions available.');
      if (mounted) setState(() => _questions = questions);
    } catch (e) {
      if (mounted) {
        setState(() => _error = (e is ApiException && e.status == 503)
            ? 'The quiz is not available right now (Spotify is not configured on the server).'
            : e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _player.stop();
    } catch (_) {/* abaikan */}
    if (mounted && _playing) setState(() => _playing = false);
  }

  Future<void> _togglePreview(String url) async {
    try {
      if (_playing) {
        await _player.stop();
        if (mounted) setState(() => _playing = false);
      } else {
        await _player.play(UrlSource(url));
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this preview.')));
      }
    }
  }

  void _pick(String option) {
    if (_picked != null) return;
    _stopAudio();
    setState(() {
      _picked = option;
      if (option == _questions[_index].answer) _score++;
    });
  }

  Future<void> _next() async {
    await _stopAudio();
    if (_index + 1 >= _questions.length) {
      await _finish();
      return;
    }
    if (mounted) {
      setState(() {
        _index++;
        _picked = null;
      });
    }
  }

  Future<void> _finish() async {
    int? best = _score;
    try {
      final uid = currentUserId();
      final previous = await LocalDb.instance.getInt(uid, QuizGamePage.bestKey);
      if (previous == null || _score > previous) {
        await LocalDb.instance.setInt(uid, QuizGamePage.bestKey, _score);
      } else {
        best = previous;
      }
    } catch (_) {/* skor tidak tersimpan */}

    // hadiah: skor 80% ke atas menampilkan satu kode promo yang sedang aktif
    String? reward;
    if (_score >= (_questions.length * 0.8).ceil()) {
      try {
        final promos = await ApiClient.instance.get('/api/promos') as List;
        if (promos.isNotEmpty) {
          final p = Map<String, dynamic>.from(promos.first as Map);
          reward = '${p['code']} • ${p['description']}';
        }
      } catch (_) {/* tanpa hadiah */}
    }
    if (!mounted) return;
    setState(() {
      _best = best;
      _reward = reward;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guess the Artist'), actions: const <Widget>[RotateButton()]),
      body: _loading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Building your quiz from Spotify...', style: TextStyle(color: AppColors.sky)),
              ]),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      const Icon(Icons.music_off_outlined, size: 48, color: AppColors.skyDim),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : (_finished ? _result() : _question()),
    );
  }

  Widget _question() {
    final q = _questions[_index];
    final answered = _picked != null;
    final isLast = _index + 1 >= _questions.length;

    return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      Row(children: <Widget>[
        Text('Question ${_index + 1} of ${_questions.length}', style: const TextStyle(color: AppColors.sky)),
        const Spacer(),
        Tag('Score $_score', icon: Icons.star_rounded),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: _index / _questions.length,
          minHeight: 6,
          backgroundColor: AppColors.skyFaint,
        ),
      ),
      const SizedBox(height: 20),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: q.image != null
              ? Image.network(
                  q.image!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverPlaceholder(),
                )
              : _coverPlaceholder(),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Who performs this track?', textAlign: TextAlign.center, style: TextStyle(color: AppColors.sky)),
      const SizedBox(height: 4),
      Text(
        q.track,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (q.album.isNotEmpty)
        Text('from "${q.album}"', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.skyDim, fontSize: 12.5)),
      if (q.previewUrl != null) ...<Widget>[
        const SizedBox(height: 12),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: () => _togglePreview(q.previewUrl!),
            icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(_playing ? 'Stop' : 'Play 30s preview'),
          ),
        ),
      ],
      const SizedBox(height: 18),
      for (final option in q.options) _option(q, option),
      if (answered) ...<Widget>[
        const SizedBox(height: 6),
        FilledButton(onPressed: _next, child: Text(isLast ? 'See result' : 'Next')),
      ],
    ]);
  }

  Widget _coverPlaceholder() => Container(
        width: 200,
        height: 200,
        color: AppColors.primary,
        child: const Icon(Icons.album_rounded, size: 80, color: AppColors.sky),
      );

  Widget _option(_Question q, String option) {
    final answered = _picked != null;
    var background = AppColors.primary;
    var border = AppColors.skyFaint;
    IconData? mark;
    if (answered) {
      if (option == q.answer) {
        background = const Color(0xFF1E7A46);
        border = AppColors.success;
        mark = Icons.check_circle;
      } else if (option == _picked) {
        background = const Color(0xFF7A2430);
        border = const Color(0xFFFF6B6B);
        mark = Icons.cancel;
      }
    }
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: background,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: answered ? null : () => _pick(option),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: <Widget>[
              Expanded(child: Text(option, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (mark != null) Icon(mark, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _result() {
    final total = _questions.length;
    final message = _score == total
        ? 'Perfect! You really know your artists.'
        : (_score * 2 >= total ? 'Nice one! Almost a music expert.' : 'Keep listening, you will get there!');
    return ListView(padding: const EdgeInsets.all(24), children: <Widget>[
      const SizedBox(height: 16),
      const Icon(Icons.emoji_events_rounded, size: 72, color: AppColors.sun),
      const SizedBox(height: 12),
      Text(
        '$_score / $total',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sky)),
      if (_best != null) ...<Widget>[
        const SizedBox(height: 8),
        Text('Your best: $_best / $total', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.skyDim)),
      ],
      if (_reward != null) ...<Widget>[
        const SizedBox(height: 20),
        AppCard(
          child: Column(children: <Widget>[
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              Icon(Icons.card_giftcard, color: AppColors.sun),
              SizedBox(width: 8),
              Text('Reward unlocked!', style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(_reward!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.butter, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Use it at checkout.', style: TextStyle(color: AppColors.sky, fontSize: 12)),
          ]),
        ),
      ],
      const SizedBox(height: 28),
      FilledButton(onPressed: _load, child: const Text('Play again')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
    ]);
  }
}
