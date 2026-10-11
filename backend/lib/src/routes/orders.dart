import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../db.dart';
import '../env.dart';
import '../services/orders_service.dart';
import '../util.dart';
import '../web.dart';

bool _hasKey() => Env.has('MIDTRANS_SERVER_KEY');

/// Membuat transaksi Snap di Midtrans Sandbox. Mengembalikan {token, redirect_url}.
Future<Map<String, dynamic>> _createSnapTransaction(Map<String, Object?> payload) async {
  final key = Env.get('MIDTRANS_SERVER_KEY');
  final resp = await http
      .post(
        Uri.parse('https://app.sandbox.midtrans.com/snap/v1/transactions'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$key:'))}',
        },
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 20));
  final text = utf8.decode(resp.bodyBytes);
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('Midtrans responded ${resp.statusCode}: $text');
  }
  final data = jsonDecode(text);
  if (data is! Map<String, dynamic>) throw Exception('Unexpected Midtrans response');
  return data;
}

void registerOrders(Router r, AppDb db) {
  // Buat order + snap token. Tanpa Midtrans key & ALLOW_DEV_ROUTES=true -> "demo order".
  r.post('/api/orders', (c) async {
    final b = c.bodyMap;
    final qn = numOf(b['qty']);
    final eventId = b['event_id'];
    final Map<String, Object?>? ev = (eventId is num || eventId is String)
        ? db.one('SELECT * FROM events WHERE id=?', <Object?>[eventId])
        : null;
    if (ev == null || qn == null || !isWhole(qn) || qn < 1 || qn > 5 || (ev['stock'] as int) < qn) {
      await c.json(400, <String, Object?>{'message': 'Invalid order or sold out'});
      return;
    }
    final q = qn.toInt();

    final endsAt = DateTime.tryParse(ev['end_time_utc'] as String);
    if (endsAt != null && endsAt.isBefore(DateTime.now())) {
      await c.json(400, <String, Object?>{'message': 'This event has already ended'});
      return;
    }
    if (!_hasKey() && !Env.devRoutes) {
      await c.json(503, <String, Object?>{'message': 'MIDTRANS_SERVER_KEY is not set in .env'});
      return;
    }

    var discount = 0;
    if (truthy(b['promo_code'])) {
      final code = b['promo_code'].toString().trim().toUpperCase();
      final p = db.one('SELECT * FROM promos WHERE code=? AND active=1', <Object?>[code]);
      if (p == null) {
        await c.json(400, <String, Object?>{'message': 'Invalid promo code'});
        return;
      }
      discount = p['discount_percent'] as int;
    }

    final price = ev['price_idr'] as int;
    final unit = ((price * (100 - discount)) / 100).round();
    final gross = unit * q;
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}-${c.userId}';
    final title = ev['title'] as String;

    String? snapToken;
    String? redirectUrl;
    if (_hasKey()) {
      try {
        final tx = await _createSnapTransaction(<String, Object?>{
          'transaction_details': <String, Object?>{'order_id': orderId, 'gross_amount': gross},
          'item_details': <Object?>[
            <String, Object?>{
              'id': ev['id'].toString(),
              'price': unit,
              'quantity': q,
              'name': title.length > 50 ? title.substring(0, 50) : title,
            },
          ],
        });
        snapToken = tx['token'] as String?;
        redirectUrl = tx['redirect_url'] as String?;
      } catch (e) {
        await c.json(502, <String, Object?>{'message': 'Payment gateway error', 'detail': e.toString()});
        return;
      }
    }

    db.run(
      'INSERT INTO transactions(order_id,user_id,event_id,qty,gross_amount,snap_token) VALUES(?,?,?,?,?,?)',
      <Object?>[orderId, c.userId, ev['id'], q, gross, snapToken],
    );
    db.run('INSERT INTO notifications(user_id,title,body) VALUES(?,?,?)', <Object?>[
      c.userId,
      'Waiting for payment',
      'Complete the payment of Rp ${formatThousands(gross)} for "$title".',
    ]);

    await c.json(201, <String, Object?>{
      'order_id': orderId,
      'gross_amount': gross,
      'snap_token': snapToken,
      'redirect_url': redirectUrl,
      'demo': !_hasKey(),
    });
  }, auth: true);

  // Webhook dari Midtrans (tanpa JWT, tapi wajib verifikasi signature)
  r.post('/api/orders/notification', (c) async {
    final b = c.bodyMap;
    final orderId = b['order_id'];
    final signature = b['signature_key'];
    final raw = '${jsString(orderId)}${jsString(b['status_code'])}${jsString(b['gross_amount'])}'
        '${Env.get('MIDTRANS_SERVER_KEY')}';
    final expected = sha512.convert(utf8.encode(raw)).toString();
    if (signature is! String || expected != signature) {
      await c.empty(403);
      return;
    }

    final tx = db.one('SELECT order_id FROM transactions WHERE order_id=?', <Object?>[orderId]);
    if (tx == null) {
      await c.empty(404);
      return;
    }

    const map = <String, String>{
      'settlement': 'paid',
      'capture': 'paid',
      'expire': 'expired',
      'cancel': 'failed',
      'deny': 'failed',
    };
    final status = map[(b['transaction_status'] ?? '').toString()];
    if (status != null) settleOrder(db, orderId.toString(), status);
    await c.empty(200);
  });

  // Daftar transaksi user
  r.get('/api/orders', (c) async {
    final rows = db.all(
      '''SELECT tr.*, e.title, e.artist, e.venue_name, e.start_time_utc
       FROM transactions tr JOIN events e ON e.id = tr.event_id
       WHERE tr.user_id = ? ORDER BY tr.created_at DESC, tr.order_id DESC''',
      <Object?>[c.userId],
    );
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      final token = row['snap_token'];
      out.add(<String, Object?>{
        ...row,
        'redirect_url': (token is String && token.isNotEmpty)
            ? 'https://app.sandbox.midtrans.com/snap/v2/vtweb/$token'
            : null,
      });
    }
    await c.json(200, out);
  }, auth: true);

  // Khusus demo: tandai order sebagai lunas tanpa Midtrans
  if (Env.devRoutes) {
    r.post('/api/orders/dev/simulate-paid/:orderId', (c) async {
      final tx = db.one('SELECT * FROM transactions WHERE order_id=?', <Object?>[c.params['orderId']]);
      if (tx == null || tx['user_id'] != c.userId) {
        await c.json(404, <String, Object?>{'message': 'Order not found'});
        return;
      }
      final done = settleOrder(db, tx['order_id'] as String, 'paid');
      await c.json(200, <String, Object?>{'order_id': tx['order_id'], 'status': done?['status']});
    }, auth: true);
  }
}
