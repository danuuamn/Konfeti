import '../db.dart';
import '../env.dart';
import '../services/users.dart';
import '../web.dart';

void registerNotifications(Router r, AppDb db, AppDb udb) {
  r.get('/api/notifications', (c) async {
    await c.json(
      200,
      await db.all('SELECT * FROM notifications WHERE user_id=? ORDER BY id DESC LIMIT 50', <Object?>[c.userId]),
    );
  }, auth: true);

  r.post('/api/notifications/read-all', (c) async {
    await db.run('UPDATE notifications SET is_read=1 WHERE user_id=?', <Object?>[c.userId]);
    await c.json(200, <String, Object?>{'ok': true});
  }, auth: true);

  r.post('/api/notifications/:id/read', (c) async {
    final nid = int.tryParse(c.params['id'] ?? '');
    if (nid != null) {
      await db.run('UPDATE notifications SET is_read=1 WHERE id=? AND user_id=?', <Object?>[nid, c.userId]);
    }
    await c.json(200, <String, Object?>{'ok': true});
  }, auth: true);

  // Khusus demo: kirim notifikasi promo ke SEMUA user
  if (Env.devRoutes) {
    r.post('/api/notifications/dev/promo', (c) async {
      final b = c.bodyMap;
      final title = (b['title'] ?? 'Special promo!').toString();
      final body = (b['body'] ?? 'Use code WEEKEND15 for 15% off this weekend.').toString();
      final sent = await notifyAllUsers(db, udb, title, body);
      await c.json(200, <String, Object?>{'sent_to': sent});
    });
  }
}
