import '../db.dart';
import '../util.dart';
import 'blockchain.dart';

(String, String)? _message(String status, String title, int qty) {
  switch (status) {
    case 'paid':
      return ('Payment successful', 'Your $qty ticket(s) for "$title" are ready in My Tickets.');
    case 'expired':
      return ('Payment expired', 'The payment for "$title" has expired. Please place a new order.');
    case 'failed':
      return ('Payment failed', 'The payment for "$title" was cancelled or denied.');
  }
  return null;
}

/// Ubah status order. Idempotent: order yang sudah "paid" tidak pernah diturunkan,
/// dan tiket + block hanya dibuat satu kali saat transisi ke "paid".
/// (UPDATE bersyarat di awal transaksi memastikan hanya satu proses yang "menang",
/// walau webhook dan sinkronisasi berjalan bersamaan.)
Future<Map<String, Object?>?> settleOrder(AppDb db, String orderId, String status) async {
  final tx = await db.one('SELECT * FROM transactions WHERE order_id=?', <Object?>[orderId]);
  if (tx == null) return null;
  if (tx['status'] == status || tx['status'] == 'paid') return tx;

  final ev = await db.one('SELECT title FROM events WHERE id=?', <Object?>[tx['event_id']]);
  final String title = ev == null ? 'your event' : ev['title'] as String;
  final int qty = tx['qty'] as int;
  final int userId = tx['user_id'] as int;
  final Object? eventId = tx['event_id'];

  await db.transaction<void>((t) async {
    final changed = (await t.run(
      "UPDATE transactions SET status=? WHERE order_id=? AND status <> ? AND status <> 'paid'",
      <Object?>[status, orderId, status],
    ))
        .changes;
    if (changed != 1) return; // sudah diproses proses lain

    if (status == 'paid') {
      for (var i = 0; i < qty; i++) {
        final code = 'TKT-${randomHex(6)}';
        await t.run(
          'INSERT INTO tickets(ticket_code,order_id,event_id,user_id) VALUES(?,?,?,?)',
          <Object?>[code, orderId, eventId, userId],
        );
        await addBlock(t, code, userId);
      }
      await t.run(
        'UPDATE events SET stock = CASE WHEN stock > ? THEN stock - ? ELSE 0 END WHERE id = ?',
        <Object?>[qty, qty, eventId],
      );
      if (tx['tier_id'] != null) {
        await t.run(
          'UPDATE ticket_tiers SET stock = CASE WHEN stock > ? THEN stock - ? ELSE 0 END WHERE id = ?',
          <Object?>[qty, qty, tx['tier_id']],
        );
      }
    }
    final m = _message(status, title, qty);
    if (m != null) {
      await t.run('INSERT INTO notifications(user_id,title,body) VALUES(?,?,?)', <Object?>[userId, m.$1, m.$2]);
    }
  });

  return db.one('SELECT * FROM transactions WHERE order_id=?', <Object?>[orderId]);
}
