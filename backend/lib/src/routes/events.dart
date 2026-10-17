import '../db.dart';
import '../web.dart';

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

    var sql = 'SELECT * FROM events WHERE (title LIKE ? OR artist LIKE ? OR lineup LIKE ?)';
    final params = <Object?>['%$q%', '%$q%', '%$q%'];
    if (category != null && category.isNotEmpty) {
      sql += ' AND category=?';
      params.add(category);
    }
    await c.json(200, db.all('$sql ORDER BY $order', params));
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
    await c.json(200, e);
  });
}
