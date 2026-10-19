import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/local_db.dart';
import '../shell/shell_nav.dart';
import '../tickets/artist_section.dart';
import 'memory_game_page.dart';
import 'quiz_game_page.dart';
import 'tilt_game_page.dart';

/// Tab Entertainment: mini games, trailer / video live, dan profil artis dari Spotify.
class FunPage extends StatefulWidget {
  const FunPage({super.key});

  @override
  State<FunPage> createState() => _FunPageState();
}

class _FunPageState extends State<FunPage> {
  /// Posisi tab Entertainment di bottom navigation (lihat main_shell.dart).
  static const int _tabIndex = 3;

  bool _started = false;
  bool _loading = false;
  String? _error;
  List<Event> _events = <Event>[];
  String? _selectedArtist;
  int? _quizBest;
  int? _memoryBest;
  int? _tiltBest;

  @override
  void initState() {
    super.initState();
    // IndexedStack membangun semua tab sejak awal; data baru diambil saat tab ini pertama kali dibuka.
    ShellNav.tab.addListener(_onTab);
    _onTab();
  }

  @override
  void dispose() {
    ShellNav.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (ShellNav.tab.value != _tabIndex) return;
    _loadBest();
    if (!_started) {
      _started = true;
      _loadEvents();
    }
  }

  Future<void> _loadBest() async {
    try {
      final uid = currentUserId();
      final quiz = await LocalDb.instance.getInt(uid, QuizGamePage.bestKey);
      final memory = await LocalDb.instance.getInt(uid, MemoryGamePage.bestKey);
      final tilt = await LocalDb.instance.getInt(uid, TiltGamePage.bestKey);
      if (mounted) {
        setState(() {
          _quizBest = quiz;
          _memoryBest = memory;
          _tiltBest = tilt;
        });
      }
    } catch (_) {/* skor tidak tampil, game tetap jalan */}
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.get('/api/events') as List;
      final events = data.map((e) => Event.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (mounted) setState(() => _events = events);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _artists {
    final seen = <String>{};
    for (final e in _events) {
      for (final a in e.artists) {
        if (a.trim().isNotEmpty) seen.add(a.trim());
      }
    }
    return seen.toList();
  }

  Future<void> _play(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    _loadBest();
  }

  Future<void> _watch(String query) async {
    try {
      final uri = Uri.https('www.youtube.com', '/results', <String, String>{'search_query': query});
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open YouTube.');
    } catch (_) {
      _snack('Could not open YouTube.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final artists = _artists;
    final selected = artists.isEmpty ? null : (artists.contains(_selectedArtist) ? _selectedArtist! : artists.first);
    final videos = _events.where((e) => !e.hasEnded).take(8).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Entertainment'), actions: const <Widget>[RotateButton()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: <Widget>[
        const SectionHeader('Mini Games', padding: EdgeInsets.fromLTRB(0, 8, 0, 10)),
        _gameCard(
          icon: Icons.music_note_rounded,
          title: 'Guess the Artist',
          subtitle: 'Hear or read a track and pick who performs it. Powered by Spotify.',
          best: _quizBest == null ? 'No score yet' : 'Best: $_quizBest/${QuizGamePage.questionCount}',
          onPlay: () => _play(const QuizGamePage()),
        ),
        _gameCard(
          icon: Icons.grid_view_rounded,
          title: 'Concert Memory',
          subtitle: 'Match all the pairs in as few moves as you can.',
          best: _memoryBest == null ? 'No score yet' : 'Best: $_memoryBest moves',
          onPlay: () => _play(const MemoryGamePage()),
        ),
        _gameCard(
          icon: Icons.screen_rotation_alt_rounded,
          title: 'Tilt Catch',
          subtitle: 'Tilt your phone like a steering wheel to catch the confetti. Uses the gyroscope.',
          best: _tiltBest == null ? 'No score yet' : 'Best: $_tiltBest pts',
          onPlay: () => _play(const TiltGamePage()),
        ),
        const SectionHeader('Trailers & Live Videos', padding: EdgeInsets.fromLTRB(0, 18, 0, 10)),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_error != null)
          Row(children: <Widget>[
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _loadEvents, child: const Text('Retry')),
          ])
        else if (videos.isEmpty)
          const Text('No upcoming events yet.', style: TextStyle(color: AppColors.sky))
        else
          for (final e in videos) _videoTile(e),
        if (selected != null) ...<Widget>[
          const SectionHeader('Discover Artists', padding: EdgeInsets.fromLTRB(0, 18, 0, 10)),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => CategoryPill(
                label: artists[i],
                selected: artists[i] == selected,
                onTap: () => setState(() => _selectedArtist = artists[i]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // key = nama artis, jadi widget (dan pemutar audio) dibuat ulang saat ganti artis
          ArtistSection(key: ValueKey<String>(selected), artist: selected),
        ],
      ]),
    );
  }

  Widget _gameCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String best,
    required VoidCallback onPlay,
  }) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onPlay,
      child: Row(children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppColors.sun, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: AppColors.ink, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.sky, fontSize: 12.5, height: 1.3)),
            const SizedBox(height: 8),
            Tag(best),
          ]),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.play_circle_fill, color: AppColors.sun, size: 36),
      ]),
    );
  }

  Widget _videoTile(Event e) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => _watch('${e.artists.first} live concert'),
      child: Row(children: <Widget>[
        const CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.sun,
          child: Icon(Icons.play_arrow_rounded, color: AppColors.ink, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              e.artistLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.sky, fontSize: 12.5),
            ),
          ]),
        ),
        const Icon(Icons.open_in_new, size: 20),
      ]),
    );
  }
}
