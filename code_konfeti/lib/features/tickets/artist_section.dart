import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';

/// Profil artis dari Spotify (lewat backend): foto, genre, pengikut, top tracks + preview lagu.
class ArtistSection extends StatefulWidget {
  const ArtistSection({super.key, required this.artist});
  final String artist;

  @override
  State<ArtistSection> createState() => _ArtistSectionState();
}

class _ArtistSectionState extends State<ArtistSection> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _doneSub;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _doneSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await ApiClient.instance
          .get('/api/spotify/artist', query: <String, String>{'name': widget.artist}) as Map;
      if (mounted) setState(() => _data = Map<String, dynamic>.from(j));
    } catch (e) {
      if (mounted) {
        setState(() => _error = (e is ApiException && e.status == 503)
            ? 'Artist info is not available right now.'
            : e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String? url) async {
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _togglePreview(Map<String, dynamic> track) async {
    final id = track['id'] as String?;
    final url = track['preview_url'] as String?;
    if (id == null || url == null) return;
    try {
      if (_playingId == id) {
        await _player.stop();
        setState(() => _playingId = null);
      } else {
        await _player.stop();
        await _player.play(UrlSource(url));
        setState(() => _playingId = id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playingId = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this preview.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            : _error != null
                ? Row(children: <Widget>[
                    const Icon(Icons.music_off_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ])
                : _content(theme),
    );
  }

  Widget _content(ThemeData theme) {
    final d = _data!;
    final image = d['image'] as String?;
    final genres = (d['genres'] as List? ?? <Object?>[]).whereType<String>().take(3).toList();
    final followers = (d['followers'] as num?)?.toInt();
    final tracks = (d['top_tracks'] as List? ?? <Object?>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .take(5)
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[
        CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.sky,
          backgroundImage: image != null ? NetworkImage(image) : null,
          child: image == null ? const Icon(Icons.person, size: 32) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(d['name']?.toString() ?? widget.artist, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (followers != null)
              Text('${NumberFormat.compact().format(followers)} followers', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sky)),
          ]),
        ),
      ]),
      if (genres.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
          for (final g in genres) Tag(g),
        ]),
      ],
      const SizedBox(height: 8),
      Text('Top tracks', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (tracks.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No tracks available.')),
      for (final t in tracks) _trackTile(t),
      const SizedBox(height: 4),
      Row(children: <Widget>[
        Expanded(
          child: Text('Powered by Spotify', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sky)),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _open(d['spotify_url'] as String?),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Open in Spotify'),
        ),
      ]),
    ]);
  }

  Widget _trackTile(Map<String, dynamic> t) {
    final image = t['image'] as String?;
    final hasPreview = t['preview_url'] != null;
    final playing = _playingId == t['id'];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: image != null
            ? Image.network(image, width: 44, height: 44, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44, child: Icon(Icons.music_note)))
            : const SizedBox(width: 44, height: 44, child: Icon(Icons.music_note)),
      ),
      title: Text(t['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(t['album']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky)),
      trailing: hasPreview
          ? IconButton(
              tooltip: playing ? 'Stop preview' : 'Play 30s preview',
              icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 30, color: AppColors.sun),
              onPressed: () => _togglePreview(t),
            )
          : IconButton(
              tooltip: 'Listen on Spotify',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _open(t['spotify_url'] as String?),
            ),
    );
  }
}
