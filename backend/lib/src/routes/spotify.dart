import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db.dart';
import '../env.dart';
import '../errors.dart';
import '../util.dart';
import '../web.dart';

// Spotify Web API lewat server (Client Credentials), supaya client secret tidak ada di aplikasi.
class _Cached {
  _Cached(this.data, this.expires);
  final Map<String, Object?> data;
  final DateTime expires;
}

class _Result {
  const _Result(this.value, this.error);
  final Map<String, dynamic>? value;
  final Object? error;
  bool get ok => error == null && value != null;
}

final Map<String, _Cached> _cache = <String, _Cached>{};
String? _token;
DateTime _tokenExpires = DateTime.fromMillisecondsSinceEpoch(0);
const Duration _ttl = Duration(minutes: 10);

Future<String> _getToken() async {
  final cached = _token;
  if (cached != null && DateTime.now().isBefore(_tokenExpires)) return cached;

  final id = Env.get('SPOTIFY_CLIENT_ID');
  final secret = Env.get('SPOTIFY_CLIENT_SECRET');
  if (id.isEmpty || secret.isEmpty) {
    throw ApiError(503, 'SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET are not set in .env');
  }
  final resp = await http
      .post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: <String, String>{
          'Authorization': 'Basic ${base64Encode(utf8.encode('$id:$secret'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      )
      .timeout(const Duration(seconds: 10));
  if (resp.statusCode != 200) {
    throw ApiError(502, 'Spotify token error ${resp.statusCode} (check your client id/secret)');
  }
  final j = jsonDecode(utf8.decode(resp.bodyBytes));
  if (j is! Map || j['access_token'] is! String) throw ApiError(502, 'Spotify token error (bad response)');
  final expiresIn = (j['expires_in'] is num) ? (j['expires_in'] as num).toInt() : 3600;
  _token = j['access_token'] as String;
  _tokenExpires = DateTime.now().add(Duration(seconds: expiresIn - 60));
  return _token!;
}

Future<Map<String, dynamic>> _spotifyGet(String path) async {
  final token = await _getToken();
  final resp = await http.get(
    Uri.parse('https://api.spotify.com/v1$path'),
    headers: <String, String>{'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 10));
  if (resp.statusCode == 404) throw ApiError(404, 'Not found on Spotify');
  if (resp.statusCode != 200) throw ApiError(502, 'Spotify error ${resp.statusCode}');
  final j = jsonDecode(utf8.decode(resp.bodyBytes));
  if (j is! Map<String, dynamic>) throw ApiError(502, 'Spotify error (bad response)');
  return j;
}

Future<_Result> _settle(Future<Map<String, dynamic>> f) async {
  try {
    return _Result(await f, null);
  } catch (e) {
    return _Result(null, e);
  }
}

String? _firstImage(Object? images) {
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first is Map && first['url'] is String) return first['url'] as String;
  }
  return null;
}

Map<String, Object?> _mapTrack(Map t) {
  final album = t['album'];
  final ext = t['external_urls'];
  return <String, Object?>{
    'id': t['id'],
    'name': t['name'],
    'album': album is Map ? album['name'] : null,
    'image': album is Map ? _firstImage(album['images']) : null,
    // Spotify tidak lagi menyediakan preview_url untuk semua track; bisa null
    'preview_url': (t['preview_url'] is String && (t['preview_url'] as String).isNotEmpty) ? t['preview_url'] : null,
    'spotify_url': ext is Map ? ext['spotify'] : null,
    'duration_ms': t['duration_ms'],
  };
}

Future<Map<String, Object?>> _loadArtist({String? id, String? name}) async {
  final key = 'a:${id ?? name!.toLowerCase()}';
  final hit = _cache[key];
  if (hit != null && hit.expires.isAfter(DateTime.now())) return hit.data;

  var artistId = id;
  if (artistId == null) {
    final s = await _spotifyGet('/search?type=artist&limit=1&q=${Uri.encodeComponent(name!)}');
    final artists = s['artists'];
    final items = artists is Map ? artists['items'] : null;
    final first = (items is List && items.isNotEmpty) ? items.first : null;
    if (first is! Map || first['id'] is! String) throw ApiError(404, 'Artist not found on Spotify');
    artistId = first['id'] as String;
  }

  final results = await Future.wait<_Result>(<Future<_Result>>[
    _settle(_spotifyGet('/artists/$artistId')),
    _settle(_spotifyGet('/artists/$artistId/top-tracks?market=ID')),
    _settle(_spotifyGet('/artists/$artistId/albums?include_groups=album,single&limit=10&market=ID')),
  ]);
  final artistRes = results[0];
  final topRes = results[1];
  final albumsRes = results[2];
  if (!artistRes.ok) {
    final err = artistRes.error;
    if (err is ApiError) throw err;
    throw ApiError(502, 'Spotify unavailable');
  }
  final a = artistRes.value!;

  var tracks = <Map<String, Object?>>[];
  if (topRes.ok) {
    try {
      final list = topRes.value!['tracks'] as List;
      tracks = list.map((t) => _mapTrack(t as Map)).toList();
    } catch (_) {
      tracks = <Map<String, Object?>>[];
    }
  }
  if (tracks.isEmpty) {
    // cadangan: cari track lewat search bila endpoint top-tracks tidak tersedia
    try {
      final s = await _spotifyGet(
        '/search?type=track&limit=10&q=${Uri.encodeComponent('artist:${a['name']}')}',
      );
      final tracksObj = s['tracks'];
      final items = tracksObj is Map ? tracksObj['items'] : null;
      if (items is List) {
        for (final t in items) {
          if (t is! Map) continue;
          final artistsOfTrack = t['artists'];
          final matches = artistsOfTrack is List && artistsOfTrack.any((x) => x is Map && x['id'] == artistId);
          if (matches) tracks.add(_mapTrack(t));
        }
      }
    } catch (_) {
      tracks = <Map<String, Object?>>[];
    }
  }

  final albums = <Map<String, Object?>>[];
  if (albumsRes.ok) {
    final items = albumsRes.value!['items'];
    if (items is List) {
      for (final al in items) {
        if (al is! Map) continue;
        final ext = al['external_urls'];
        albums.add(<String, Object?>{
          'id': al['id'],
          'name': al['name'],
          'image': _firstImage(al['images']),
          'release_date': al['release_date'],
          'type': al['album_type'],
          'spotify_url': ext is Map ? ext['spotify'] : null,
        });
      }
    }
  }

  final followers = a['followers'];
  final ext = a['external_urls'];
  final data = <String, Object?>{
    'id': artistId,
    'name': a['name'],
    'image': _firstImage(a['images']),
    'genres': a['genres'] is List ? a['genres'] : <Object?>[],
    'followers': followers is Map ? followers['total'] : null,
    'popularity': a['popularity'],
    'spotify_url': ext is Map ? ext['spotify'] : null,
    'top_tracks': tracks,
    'albums': albums,
  };
  _cache[key] = _Cached(data, DateTime.now().add(_ttl));
  return data;
}

Future<void> _sendError(Ctx c, Object e) async {
  final status = e is ApiError ? e.status : 502;
  final message = e is ApiError ? e.message : 'Spotify unavailable';
  await c.json(status, <String, Object?>{'message': message});
}

void registerSpotify(Router r, AppDb db) {
  // GET /api/spotify/artist?name=Tulus   atau   ?id=<spotify_artist_id>
  r.get('/api/spotify/artist', (c) async {
    final id = c.query['id'];
    final name = c.query['name'];
    final hasId = id != null && id.isNotEmpty;
    final hasName = name != null && name.isNotEmpty;
    if (!hasId && !hasName) {
      await c.json(400, <String, Object?>{'message': 'id or name is required'});
      return;
    }
    try {
      final data = await _loadArtist(id: hasId ? id : null, name: hasName ? name : null);
      await c.json(200, data);
    } catch (e) {
      await _sendError(c, e);
    }
  }, auth: true);

  // GET /api/spotify/quiz?n=5  -> soal "Guess the Artist" dari artis-artis di tabel events
  r.get('/api/spotify/quiz', (c) async {
    final nRaw = numOf(c.query['n']);
    var n = (nRaw == null || nRaw == 0) ? 5 : nRaw.toInt();
    if (n < 1) n = 1;
    if (n > 8) n = 8;

    final artistRows = await db.all("SELECT DISTINCT artist FROM events WHERE artist IS NOT NULL AND artist <> ''");
    final names = artistRows.map((row) => row['artist'] as String).toList();
    if (names.length < 4) {
      await c.json(400, <String, Object?>{'message': 'Need at least 4 different artists in events'});
      return;
    }

    try {
      final pool = shuffled(names);
      final questions = <Map<String, Object?>>[];
      for (var i = 0; i < pool.length && questions.length < n; i++) {
        final correct = pool[i];
        Map<String, Object?> data;
        try {
          data = await _loadArtist(name: correct);
        } catch (e) {
          if (e is ApiError && e.status == 503) rethrow; // key belum diisi -> hentikan
          continue; // artis tidak ketemu -> lewati
        }
        final topTracks = data['top_tracks'] as List<Map<String, Object?>>;
        if (topTracks.isEmpty) continue;
        final track = shuffled(topTracks).first;
        final others = shuffled(names.where((x) => x != correct).toList()).take(3).toList();
        questions.add(<String, Object?>{
          'track_name': track['name'],
          'album_name': track['album'],
          'album_image': track['image'],
          'preview_url': track['preview_url'],
          'options': shuffled(<String>[correct, ...others]),
          'answer': correct,
        });
      }
      if (questions.isEmpty) throw ApiError(502, 'Could not build quiz questions from Spotify');
      await c.json(200, questions);
    } catch (e) {
      await _sendError(c, e);
    }
  }, auth: true);
}

/// Foto artis dari Spotify (dipakai bin/seed.dart). Null bila key belum diisi / artis tidak ditemukan.
Future<String?> fetchArtistImage(String name) async {
  try {
    final s = await _spotifyGet('/search?type=artist&limit=1&q=${Uri.encodeComponent(name)}');
    final artists = s['artists'];
    final items = artists is Map ? artists['items'] : null;
    final first = (items is List && items.isNotEmpty) ? items.first : null;
    if (first is! Map) return null;
    return _firstImage(first['images']);
  } catch (_) {
    return null;
  }
}