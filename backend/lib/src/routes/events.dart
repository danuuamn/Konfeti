import '../db.dart';
import '../env.dart';
import '../web.dart';

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
List<Map<String, Object?>> _enrich(Ctx c, AppDb db, List<Map<String, Object?>> events) {
  final tiers = db.all(
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

    var sql = 'SELECT * FROM events WHERE (title LIKE ? OR artist LIKE ?)';
    final params = <Object?>['%$q%', '%$q%'];
    if (category != null && category.isNotEmpty) {
      sql += ' AND category=?';
      params.add(category);
    }
    await c.json(200, _enrich(c, db, db.all('$sql ORDER BY $order', params)));
  });

  // harus didaftarkan sebelum '/api/events/:id'
  r.get('/api/events/categories', (c) async {
    final rows = db.all('SELECT DISTINCT category FROM events ORDER BY category');
    await c.json(200, rows.map((row) => row['category']).toList());
  });

  r.get('/api/events/:id', (c) async {
    final e = db.one('SELECT * FROM events WHERE id=?', <Object?>[c.params['id']]);
    if (e == null) {
      await c.json(404, <String, Object?>{'message': 'Event not found'});
      return;
    }
    await c.json(200, _enrich(c, db, <Map<String, Object?>>[e]).first);
  });
}
