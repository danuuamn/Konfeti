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
Map<String, Object?>? settleOrder(AppDb db, String orderId, String status) {
  final tx = db.one('SELECT * FROM transactions WHERE order_id=?', <Object?>[orderId]);
  if (tx == null) return null;
  if (tx['status'] == status || tx['status'] == 'paid') return tx;

  final ev = db.one('SELECT title FROM events WHERE id=?', <Object?>[tx['event_id']]);
  final String title = ev == null ? 'your event' : ev['title'] as String;
  final int qty = tx['qty'] as int;
  final int userId = tx['user_id'] as int;
  final Object? eventId = tx['event_id'];

  db.transaction<void>(() {
    if (status == 'paid') {
      for (var i = 0; i < qty; i++) {
        final code = 'TKT-${randomHex(6)}';
        db.run(
          'INSERT INTO tickets(ticket_code,order_id,event_id,user_id) VALUES(?,?,?,?)',
          <Object?>[code, orderId, eventId, userId],
        );
        addBlock(db, code, userId);
      }
      db.run('UPDATE events SET stock = MAX(stock - ?, 0) WHERE id = ?', <Object?>[qty, eventId]);
    }
    db.run('UPDATE transactions SET status=? WHERE order_id=?', <Object?>[status, orderId]);
    final m = _message(status, title, qty);
    if (m != null) {
      db.run('INSERT INTO notifications(user_id,title,body) VALUES(?,?,?)', <Object?>[userId, m.$1, m.$2]);
    }
  });

  return db.one('SELECT * FROM transactions WHERE order_id=?', <Object?>[orderId]);
}
