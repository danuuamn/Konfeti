// Smoke test alur penuh (HTTP saja). Jalankan server dulu (dart run bin/server.dart),
// lalu di terminal lain: dart run test/smoke.dart
// Tidak butuh API key: pembayaran disimulasikan (demo order / webhook bertanda tangan).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:konfeti_backend/src/env.dart';

late final String base;
int passed = 0;
int failed = 0;

void check(String name, bool cond, [String extra = '']) {
  if (cond) {
    passed++;
    print('  PASS  $name');
  } else {
    failed++;
    print('  FAIL  $name $extra');
  }
}

class Res {
  Res(this.status, this.data);
  final int status;
  final dynamic data;
}

Future<Res> call(String method, String path, {Object? body, String? token}) async {
  final req = http.Request(method, Uri.parse(base + path));
  req.headers['Content-Type'] = 'application/json';
  if (token != null) req.headers['Authorization'] = 'Bearer $token';
  if (body != null) req.body = jsonEncode(body);
  final streamed = await req.send();
  final res = await http.Response.fromStream(streamed);
  dynamic data;
  try {
    data = jsonDecode(res.body);
  } catch (_) {
    data = null; // respons kosong
  }
  return Res(res.statusCode, data);
}

Future<Res> webhook(String orderId, String grossAmount, String txStatus) {
  const statusCode = '200';
  final key = Env.get('MIDTRANS_SERVER_KEY');
  final sig = sha512.convert(utf8.encode('$orderId$statusCode$grossAmount$key')).toString();
  return call('POST', '/api/orders/notification', body: <String, Object?>{
    'order_id': orderId,
    'status_code': statusCode,
    'gross_amount': grossAmount,
    'signature_key': sig,
    'transaction_status': txStatus,
  });
}

const png1px =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

bool hasNotif(Res r, bool Function(Map n) test) =>
    r.data is List && (r.data as List).any((n) => n is Map && test(n));

Future<void> main() async {
  Env.load();
  base = Platform.environment['BASE_URL'] ?? 'http://localhost:${Env.get('PORT', '3000')}';
  print('Testing $base\n');

  try {
    print('[1] Health & events');
    var r = await call('GET', '/api/health');
    check('health returns ok', r.status == 200 && r.data['status'] == 'ok');
    final health = r.data as Map;
    final features = (health['features'] as Map?) ?? {};
    final dev = health['dev'] == true;
    r = await call('GET', '/api/events');
    check('events list not empty (run "dart run bin/seed.dart")', r.status == 200 && (r.data as List).isNotEmpty);
    final events = (r.data as List).cast<Map>();
    r = await call('GET', '/api/events?sort=price_asc');
    final l = r.data as List;
    check('sort price ascending', (l.first['price_idr'] as num) <= (l.last['price_idr'] as num));
    r = await call('GET', '/api/events?category=Rock');
    check('filter by category',
        (r.data as List).isNotEmpty && (r.data as List).every((e) => e['category'] == 'Rock'));
    r = await call('GET', '/api/events?q=tulus');
    check('search by keyword', (r.data as List).isNotEmpty);
    r = await call('GET', '/api/events/categories');
    check('categories list', r.data is List && (r.data as List).isNotEmpty);

    print('\n[2] Auth & profile');
    final email = 'tester_${DateTime.now().millisecondsSinceEpoch}@mail.com';
    r = await call('POST', '/api/auth/register',
        body: {'name': 'Tester', 'email': email, 'password': 'secret123'});
    check('register returns 201 + token', r.status == 201 && r.data['token'] != null);
    r = await call('POST', '/api/auth/register',
        body: {'name': 'Tester', 'email': email, 'password': 'secret123'});
    check('duplicate email rejected (409)', r.status == 409);
    r = await call('POST', '/api/auth/register', body: {'name': 'X', 'email': 'bad', 'password': '123'});
    check('invalid input rejected (400)', r.status == 400);
    r = await call('POST', '/api/auth/login', body: {'email': email, 'password': 'wrongpass'});
    check('wrong password rejected (401)', r.status == 401);
    r = await call('POST', '/api/auth/login', body: {'email': email, 'password': 'secret123'});
    check('login returns token', r.status == 200 && r.data['token'] != null);
    final token = r.data['token'] as String;
    r = await call('GET', '/api/auth/me', token: token);
    check('/me works with token', r.status == 200 && r.data['email'] == email);
    r = await call('GET', '/api/auth/me');
    check('/me without token is 401', r.status == 401);
    r = await call('PUT', '/api/auth/me', body: {'name': 'Tester Baru'}, token: token);
    check('update profile name', r.status == 200 && r.data['name'] == 'Tester Baru');
    r = await call('POST', '/api/auth/me/avatar', body: {'image_base64': png1px}, token: token);
    check('upload avatar', r.status == 200 && r.data['avatar_url'] != null);
    if (r.data is Map && r.data['avatar_url'] != null) {
      final img = await http.get(Uri.parse(base + (r.data['avatar_url'] as String)));
      check('avatar file is served', img.statusCode == 200);
    }
    r = await call('POST', '/api/auth/me/avatar',
        body: {'image_base64': base64Encode(utf8.encode('not an image'))}, token: token);
    check('non-image upload rejected (400)', r.status == 400);
    r = await call('GET', '/api/notifications', token: token);
    check('welcome promo notification exists', hasNotif(r, (n) => '${n['title']}'.startsWith('Welcome')));

    print('\n[3] Promos & exchange rates');
    r = await call('GET', '/api/promos');
    check('promo list', r.status == 200 && (r.data as List).isNotEmpty);
    r = await call('GET', '/api/promos/validate?code=konfeti10');
    check('promo code validates (case-insensitive)', r.status == 200 && r.data['discount_percent'] == 10);
    r = await call('GET', '/api/promos/validate?code=NOPE');
    check('invalid promo rejected (404)', r.status == 404);
    r = await call('GET', '/api/rates');
    check('rates has IDR/USD/EUR/JPY',
        r.status == 200 && ['IDR', 'USD', 'EUR', 'JPY'].every((c) => (r.data['rates'][c] as num) > 0));

    print('\n[4] Demo order -> simulate payment -> tickets');
    final now = DateTime.now().toUtc();
    final ev = events.firstWhere(
        (e) => (e['stock'] as int) > 5 && DateTime.parse(e['end_time_utc'] as String).isAfter(now));
    final evId = ev['id'];
    r = await call('GET', '/api/events/$evId');
    final tiers = ((r.data['tiers'] as List?) ?? <dynamic>[]).cast<Map>();
    check('event detail lists ticket categories', tiers.isNotEmpty);
    final tier = tiers.firstWhere((t) => (t['stock'] as int) > 5, orElse: () => tiers.first);
    final tierId = tier['id'];
    final unitPrice = tier['price_idr'] as int;
    final events2 = events.where((e) => (e['tiers'] as List).length > 1).toList();
    check('some events have many categories and some only one',
        events2.isNotEmpty && events.any((e) => (e['tiers'] as List).length == 1));
    r = await call('POST', '/api/orders', body: {'event_id': evId, 'qty': 1}, token: token);
    check('order without category rejected (400)', r.status == 400);
    final otherEv = events.firstWhere((e) => e['id'] != evId && (e['tiers'] as List).isNotEmpty);
    r = await call('POST', '/api/orders',
        body: {'event_id': evId, 'qty': 1, 'tier_id': (otherEv['tiers'] as List).first['id']}, token: token);
    check('category of another event rejected (400)', r.status == 400);
    final midtransOn = features['midtrans'] == true;
    if (!midtransOn && dev) {
      final stockBefore = ev['stock'] as int;
      r = await call('POST', '/api/orders',
          body: {'event_id': evId, 'qty': 2, 'tier_id': tierId, 'promo_code': 'KONFETI10'}, token: token);
      check('demo order created (201)', r.status == 201 && r.data['demo'] == true, jsonEncode(r.data));
      final expected = (unitPrice * 0.9).round() * 2;
      check('promo discount applied to total', r.data['gross_amount'] == expected,
          '${r.data['gross_amount']} vs $expected');
      final demoOrder = r.data['order_id'];
      r = await call('POST', '/api/orders',
          body: {'event_id': evId, 'qty': 1, 'tier_id': tierId, 'promo_code': 'BOGUS'}, token: token);
      check('order with invalid promo rejected', r.status == 400);
      r = await call('GET', '/api/orders', token: token);
      check('pending order listed',
          hasNotif(r, (o) => o['order_id'] == demoOrder && o['status'] == 'pending'));
      r = await call('POST', '/api/orders/dev/simulate-paid/$demoOrder', token: token);
      check('simulate payment', r.status == 200 && r.data['status'] == 'paid');
      r = await call('GET', '/api/tickets', token: token);
      check('2 tickets issued', r.data is List && (r.data as List).length == 2, 'got ${(r.data as List).length}');
      r = await call('GET', '/api/events/$evId');
      check('stock decreased by qty', r.data['stock'] == stockBefore - 2);
      final tierAfter = (r.data['tiers'] as List).firstWhere((t) => t['id'] == tierId);
      check('category stock decreased by qty', tierAfter['stock'] == (tier['stock'] as int) - 2);
      r = await call('GET', '/api/notifications', token: token);
      check('"Payment successful" notification created', hasNotif(r, (n) => n['title'] == 'Payment successful'));
    } else {
      print('  skipped (Midtrans key is set or ALLOW_DEV_ROUTES is not true)');
    }

    print('\n[5] Midtrans webhook (signed) -> tickets -> blockchain');
    r = await call('POST', '/api/orders', body: {'event_id': evId, 'qty': 1, 'tier_id': tierId}, token: token);
    String code = '';
    if (r.status != 201) {
      check('order for webhook test created', false, 'status ${r.status} ${jsonEncode(r.data)}');
    } else {
      final orderId = r.data['order_id'] as String;
      final gross = r.data['gross_amount'] as int;
      r = await call('POST', '/api/orders/notification', body: {
        'order_id': orderId,
        'status_code': '200',
        'gross_amount': '$gross',
        'signature_key': 'forged',
        'transaction_status': 'settlement',
      });
      check('forged webhook rejected (403)', r.status == 403);
      final before = ((await call('GET', '/api/tickets', token: token)).data as List).length;
      r = await webhook(orderId, '$gross.00', 'settlement');
      check('valid webhook accepted (200)', r.status == 200);
      r = await webhook(orderId, '$gross.00', 'settlement');
      check('duplicate webhook is idempotent', r.status == 200);
      r = await call('GET', '/api/tickets', token: token);
      final tickets = r.data as List;
      check('exactly 1 new ticket (no duplicates)', tickets.length == before + 1,
          'got ${tickets.length - before}');
      check('ticket state is active', tickets.every((t) => t['state'] == 'active'));
      code = tickets.last['ticket_code'] as String;
      r = await call('GET', '/api/tickets/$code/verify', token: token);
      check('ticket verified on blockchain',
          r.data['ticket_registered'] == true && r.data['chain_valid'] == true);
    }

    print('\n[6] Feedback & emergency');
    r = await call('POST', '/api/feedback', body: {'rating': 5, 'message': 'Great course!'}, token: token);
    check('feedback saved', r.status == 201);
    r = await call('POST', '/api/feedback', body: {'rating': 9, 'message': 'x'}, token: token);
    check('invalid feedback rejected', r.status == 400);
    r = await call('GET', '/api/feedback', token: token);
    check('feedback list', r.data is List && (r.data as List).length == 1);
    r = await call('POST', '/api/emergency',
        body: {'event_id': evId, 'ticket_code': code, 'latitude': -7.76, 'longitude': 110.4}, token: token);
    check('emergency alert saved', r.status == 201 && r.data['ok'] == true);
    r = await call('GET', '/api/notifications', token: token);
    check('emergency notification created', hasNotif(r, (n) => n['title'] == 'Emergency alert sent'));

    print('\n[7] Features that need your own API keys (graceful errors)');
    r = await call('GET', '/api/spotify/artist?name=Tulus', token: token);
    check(features['spotify'] == true ? 'spotify works' : 'spotify without keys -> 503',
        features['spotify'] == true ? r.status == 200 : r.status == 503, 'status ${r.status}');
    r = await call('GET',
        '/api/weather?lat=${ev['latitude']}&lon=${ev['longitude']}&at=${ev['start_time_utc']}',
        token: token);
    check(features['weather'] == true ? 'weather works' : 'weather without key -> 503',
        features['weather'] == true ? r.status == 200 : r.status == 503, 'status ${r.status}');
    r = await call('POST', '/api/chat', body: {'message': 'hello'}, token: token);
    check(features['gemini'] == true ? 'chat works' : 'chat without key -> 503',
        features['gemini'] == true ? r.status == 200 : r.status == 503, 'status ${r.status}');

    print('\n[8] Tamper detection');
    if (dev && code.isNotEmpty) {
      r = await call('GET', '/api/tickets/$code/verify', token: token);
      await call('POST', '/api/tickets/dev/tamper/${r.data['block_index']}');
      r = await call('GET', '/api/tickets/$code/verify', token: token);
      check('tampered chain detected (chain_valid=false)', r.data['chain_valid'] == false);
      print('  (Info) Block database sekarang sengaja rusak. Hapus app.db lalu "dart run bin/seed.dart" untuk reset.');
    } else {
      print('  skipped (ALLOW_DEV_ROUTES is not true)');
    }
  } catch (e) {
    print('Test crashed. Is the server running? $e');
    exit(1);
  }

  print('\nResult: $passed passed, $failed failed');
  exit(failed > 0 ? 1 : 0);
}
