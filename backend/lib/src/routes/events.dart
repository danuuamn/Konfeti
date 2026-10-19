import '../db.dart';
import '../env.dart';
import '../web.dart';
import 'spotify.dart' show fetchArtistImage;

String _baseUrl(Ctx c) {
  final fixed = Env.get('PUBLIC_BASE_URL');
  if (fixed.isNotEmpty) return fixed.replaceAll(RegExp(r'/+$'), '');
  final h = c.request.headers;
  final proto = h.value('x-forwarded-proto') ?? 'http';
  final host = h.value('x-forwarded-host') ?? h.value('host');
  return host == null ? '' : '$proto://$host';
}

/// Tambahkan daftar kategori tiket (`tiers`) ke tiap event, dan ubah image_url
/// relatif (mis. /uploads/artists/x.jpg) menjadi alamat penuh.
Future<List<Map<String, Object?>>> _enrich(Ctx c, AppDb db, List<Map<String, Object?>> events) async {
  final tiers = await db.all(
    'SELECT id, event_id, name, description, price_idr, stock FROM ticket_tiers ORDER BY sort_order, id',
  );
  final byEvent = <Object?, List<Map<String, Object?>>>{};
  for (final t in tiers) {
    byEvent.putIfAbsent(t['event_id'], () => <Map<String, Object?>>[]).add(<String, Object?>{
      'id': t['id'],
      'name': t['name'],
      'description': t['description'],
      'price_idr': t['price_idr'],
      'stock': t['stock'],
    });
  }
  final base = _baseUrl(c);
  return events.map((e) {
    final img = e['image_url'];
    final absolute = (img is String && img.startsWith('/') && base.isNotEmpty) ? '$base$img' : img;
    return <String, Object?>{
      ...e,
      'image_url': absolute,
      'tiers': byEvent[e['id']] ?? <Map<String, Object?>>[],
    };
  }).toList();
}

final Map<String, DateTime> _imageTried = <String, DateTime>{};

/// Isi otomatis image_url yang masih kosong dengan foto artis dari Spotify (bila key Spotify ada).
/// Hasilnya disimpan ke database, jadi Spotify hanya dipanggil sekali per artis.
/// Mengembalikan true bila ada baris yang diubah.
Future<bool> _fillMissingImages(AppDb db, List<Map<String, Object?>> events) async {
  if (!Env.has('SPOTIFY_CLIENT_ID') || !Env.has('SPOTIFY_CLIENT_SECRET')) return false;
  final now = DateTime.now();
  final artists = <String>{};
  for (final e in events) {
    final img = e['image_url'];
    final artist = e['artist'];
    final missing = img == null || (img is String && img.isEmpty);
    if (missing && artist is String && artist.isNotEmpty) {
      final last = _imageTried[artist];
      if (last == null || now.difference(last) > const Duration(minutes: 10)) artists.add(artist);
    }
  }
  if (artists.isEmpty) return false;
  for (final a in artists) {
    _imageTried[a] = now; // jangan coba lagi terus-menerus bila gagal
  }
  var changed = false;
  await Future.wait(artists.map((a) async {
    final url = await fetchArtistImage(a).timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (url != null) {
      await db.run(
        "UPDATE events SET image_url=? WHERE artist=? AND (image_url IS NULL OR image_url='')",
        <Object?>[url, a],
      );
      changed = true;
    }
  }));
  return changed;
}

void registerEvents(Router r, AppDb db) {
  // GET /api/events?q=&category=&sort=start|price_asc|price_desc
  r.get('/api/events', (c) async {
    final q = c.query['q'] ?? '';
    final category = c.query['category'];
    final sort = c.query['sort'] ?? 'start';
    const orderMap = <String, String>{
      'price_asc': 'price_idr ASC',
      'price_desc': 'price_idr DESC',
      'start': 'start_time_utc ASC',
    };
    final order = orderMap[sort] ?? orderMap['start']!; // whitelist -> aman dari SQL injection

    var sql = "SELECT * FROM events WHERE status='active' AND (title LIKE ? OR artist LIKE ?)";
    final params = <Object?>['%$q%', '%$q%'];
    if (category != null && category.isNotEmpty) {
      sql += ' AND category=?';
      params.add(category);
    }
    var rows = await db.all('$sql ORDER BY $order', params);
    if (await _fillMissingImages(db, rows)) rows = await db.all('$sql ORDER BY $order', params);
    await c.json(200, await _enrich(c, db, rows));
  });

  // harus didaftarkan sebelum '/api/events/:id'
  r.get('/api/events/categories', (c) async {
    final rows = await db.all("SELECT DISTINCT category FROM events WHERE status='active' ORDER BY category");
    await c.json(200, rows.map((row) => row['category']).toList());
  });

  r.get('/api/events/:id', (c) async {
    final id = int.tryParse(c.params['id'] ?? '');
    var e = id == null
        ? null
        : await db.one("SELECT * FROM events WHERE id=? AND status != 'draft'", <Object?>[id]);
    if (e != null && await _fillMissingImages(db, <Map<String, Object?>>[e])) {
      e = await db.one('SELECT * FROM events WHERE id=?', <Object?>[id]);
    }
    if (e == null) {
      await c.json(404, <String, Object?>{'message': 'Event not found'});
      return;
    }
    await c.json(200, (await _enrich(c, db, <Map<String, Object?>>[e])).first);
  });
}
