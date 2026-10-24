import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../env.dart';
import '../web.dart';

/// Pengenal lagu ala Shazam lewat AudD (https://audd.io). Token API hanya ada di server.
/// Aplikasi mengirim rekaman pendek (base64) -> server meneruskan ke AudD -> hasil dinormalkan.
final RateLimiter _limiter = RateLimiter(const Duration(minutes: 1), 6);

const Set<String> _formats = <String>{'m4a', 'aac', 'mp3', 'wav', 'ogg', 'webm', '3gp'};

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

void registerRecognize(Router r) {
  r.post('/api/recognize', (c) async {
    final token = Env.get('AUDD_API_TOKEN');
    if (token.isEmpty) {
      await c.json(503, <String, Object?>{'message': 'AUDD_API_TOKEN is not set in .env'});
      return;
    }
    if (!_limiter.allow('u${c.userId}')) {
      await c.json(429, <String, Object?>{'message': 'Too many attempts. Please wait a minute and try again.'});
      return;
    }

    final audio = c.bodyMap['audio'];
    var ext = (c.bodyMap['ext'] ?? 'm4a').toString().toLowerCase();
    if (!_formats.contains(ext)) ext = 'm4a';
    Uint8List bytes;
    try {
      bytes = base64Decode(audio is String ? audio : '');
    } catch (_) {
      bytes = Uint8List(0);
    }
    if (bytes.length < 2000) {
      await c.json(400, <String, Object?>{'message': 'The recording is empty or too short.'});
      return;
    }
    if (bytes.length > 9 * 1024 * 1024) {
      await c.json(413, <String, Object?>{'message': 'The recording is too large.'});
      return;
    }

    try {
      final req = http.MultipartRequest('POST', Uri.parse('https://api.audd.io/'))
        ..fields['api_token'] = token
        ..fields['return'] = 'spotify,apple_music'
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'clip.$ext'));
      final streamed = await req.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);
      final j = _map(jsonDecode(utf8.decode(resp.bodyBytes)));
      if (j == null) {
        await c.json(502, <String, Object?>{'message': 'Song recognition service sent an unexpected answer.'});
        return;
      }
      if (j['status'] != 'success') {
        final err = _map(j['error']);
        final code = (err?['error_code'] as num?)?.toInt();
        print('AudD error: $err');
        if (code == 900 || code == 901) {
          await c.json(503, <String, Object?>{
            'message': 'Song recognition is unavailable (AudD token invalid or quota used up).',
          });
        } else {
          await c.json(502, <String, Object?>{'message': 'Song recognition failed. Please try again.'});
        }
        return;
      }

      final res = _map(j['result']);
      if (res == null || (res['title'] ?? '').toString().isEmpty) {
        print('AudD: no match (${bytes.length} bytes sent). Raw: ${utf8.decode(resp.bodyBytes).replaceAll(RegExp(r"\s+"), " ")}');
      }
      if (res == null || (res['title'] ?? '').toString().isEmpty) {
        await c.json(200, <String, Object?>{'found': false});
        return;
      }

      final spotify = _map(res['spotify']);
      final apple = _map(res['apple_music']);
      String? spotifyUrl = _map(spotify?['external_urls'])?['spotify']?.toString();
      final appleUrl = apple?['url']?.toString();
      String? artwork;
      final images = _map(spotify?['album'])?['images'];
      if (images is List && images.isNotEmpty) artwork = _map(images.first)?['url']?.toString();
      if (artwork == null) {
        final tpl = _map(apple?['artwork'])?['url']?.toString();
        if (tpl != null) artwork = tpl.replaceAll('{w}', '300').replaceAll('{h}', '300');
      }
      final link = res['song_link']?.toString();
      if ((spotifyUrl == null || spotifyUrl.isEmpty) && link != null && link.contains('spotify')) spotifyUrl = link;

      await c.json(200, <String, Object?>{
        'found': true,
        'title': res['title'],
        'artist': res['artist'],
        'album': res['album'],
        'release_date': res['release_date'],
        'spotify_url': spotifyUrl,
        'apple_music_url': appleUrl,
        'song_link': link,
        'artwork': artwork,
      });
    } catch (e) {
      print('Recognize error: $e');
      await c.json(502, <String, Object?>{'message': 'Song recognition service is unreachable. Please try again.'});
    }
  }, auth: true);
}
