import '../db.dart';
import '../env.dart';
import '../services/blockchain.dart';
import '../util.dart';
import 'orders.dart' show syncPendingOrders;
import '../web.dart';

void registerTickets(Router r, AppDb db) {
  // Daftar tiket milik user (untuk halaman "My Tickets")
  r.get('/api/tickets', (c) async {
    await syncPendingOrders(db, c.userId);
    final rows = await db.all(
      '''SELECT t.ticket_code, t.order_id, e.id AS event_id, e.title, e.artist, e.venue_name,
                e.start_time_utc, e.end_time_utc, e.latitude, e.longitude, e.is_outdoor,
                tr.tier_name,
                CASE WHEN e.end_time_utc < ?
                     THEN 'history' ELSE 'active' END AS state
         FROM tickets t JOIN events e ON e.id = t.event_id
         LEFT JOIN transactions tr ON tr.order_id = t.order_id
         WHERE t.user_id = ? ORDER BY e.start_time_utc ASC''',
      <Object?>[isoMs(DateTime.now()), c.userId],
    );
    await c.json(200, rows);
  }, auth: true);

  // Verifikasi tiket lewat blockchain
  r.get('/api/tickets/:code/verify', (c) async {
    final ticket = await db.one('SELECT user_id FROM tickets WHERE ticket_code=?', <Object?>[c.params['code']]);
    if (ticket == null || ticket['user_id'] != c.userId) {
      await c.json(404, <String, Object?>{'message': 'Ticket not found'});
      return;
    }
    final block = await db.one('SELECT * FROM blocks WHERE ticket_code=?', <Object?>[c.params['code']]);
    final chain = await verifyChain(db);
    await c.json(200, <String, Object?>{
      'ticket_registered': block != null,
      'chain_valid': chain.valid,
      'block_index': block?['idx'],
      'block_hash': block?['hash'],
      'broken_at': chain.valid ? null : chain.brokenAt,
    });
  }, auth: true);

  // ---- Khusus demo: sengaja merusak 1 block agar verifikasi gagal ----
  if (Env.devRoutes) {
    r.post('/api/tickets/dev/tamper/:idx', (c) async {
      final idx = int.tryParse(c.params['idx'] ?? '');
      if (idx != null) await db.run('UPDATE blocks SET user_id = user_id + 999 WHERE idx = ?', <Object?>[idx]);
      await c.json(200, <String, Object?>{'message': 'Block ${c.params['idx']} tampered (demo only)'});
    });
  }
}
