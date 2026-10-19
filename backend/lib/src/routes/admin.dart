import '../db.dart';
import '../services/blockchain.dart';
import '../util.dart';
import '../web.dart';

/// Semua route di sini hanya untuk akun dengan role 'admin'. Peran dicek di SERVER pada setiap request
/// (dibaca dari database, bukan dari token), jadi user biasa tidak bisa menembusnya.
Handler _adminOnly(AppDb db, Handler h) => (Ctx c) async {
      final u = await db.one('SELECT role FROM users WHERE id=?', <Object?>[c.userId]);
      if (u == null || u['role'] != 'admin') {
        await c.json(403, <String, Object?>{'message': 'Admin access required'});
        return;
      }
      await h(c);
    };

int? _int(Object? v) {
  final d = numOf(v);
  if (d == null || !isWhole(d)) return null;
  return d.toInt();
}

String? _iso(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : isoMs(d);
}

int _limit(Ctx c, {int def = 50, int max = 200}) {
  final n = int.tryParse(c.query['limit'] ?? '') ?? def;
  return n < 1 ? def : (n > max ? max : n);
}

int _offset(Ctx c) {
  final n = int.tryParse(c.query['offset'] ?? '') ?? 0;
  return n < 0 ? 0 : n;
}

class _Parsed {
  _Parsed(this.fields, [this.error]);
  final Map<String, Object?> fields;
  final String? error;
}

const Set<String> _eventStatuses = <String>{'active', 'draft', 'cancelled'};

/// Validasi field event. Hanya field yang ada di body yang diproses (untuk update);
/// saat [create] true, field wajib harus ada.
_Parsed _parseEvent(Map<String, dynamic> b, {required bool create}) {
  final f = <String, Object?>{};
  bool has(String k) => b.containsKey(k);
  _Parsed bad(String m) => _Parsed(f, m);

  if (create || has('title')) {
    final v = b['title'];
    if (v is! String || v.trim().isEmpty || v.length > 120) return bad('Title is required (max 120 characters)');
    f['title'] = v.trim();
  }
  for (final key in const <String>['artist', 'category', 'venue_name', 'spotify_artist_id']) {
    if (has(key)) {
      final v = b[key];
      if (v != null && (v is! String || v.length > 120)) return bad('Invalid $key');
      f[key] = (v is String && v.trim().isNotEmpty) ? v.trim() : null;
    }
  }
  if (has('image_url')) {
    final v = b['image_url'];
    if (v != null && (v is! String || v.length > 500)) return bad('Invalid image_url');
    f['image_url'] = (v is String && v.trim().isNotEmpty) ? v.trim() : null;
  }
  for (final key in const <String>['latitude', 'longitude']) {
    if (has(key)) {
      final v = b[key];
      if (v == null) {
        f[key] = null;
      } else {
        final d = numOf(v);
        final limit = key == 'latitude' ? 90.0 : 180.0;
        if (d == null || d < -limit || d > limit) return bad('Invalid $key');
        f[key] = d;
      }
    }
  }
  if (has('is_outdoor')) {
    f['is_outdoor'] = (b['is_outdoor'] == true || b['is_outdoor'] == 1) ? 1 : 0;
  }
  for (final key in const <String>['start_time_utc', 'end_time_utc']) {
    if (create || has(key)) {
      final iso = _iso(b[key]);
      if (iso == null) return bad('$key must be a valid date-time (ISO 8601)');
      f[key] = iso;
    }
  }
  if (has('status')) {
    final v = b['status'];
    if (v is! String || !_eventStatuses.contains(v)) return bad('status must be active, draft or cancelled');
    f['status'] = v;
  }
  for (final key in const <String>['price_idr', 'stock']) {
    if (has(key)) {
      final v = _int(b[key]);
      if (v == null || v < 0) return bad('$key must be a whole number >= 0');
      f[key] = v;
    }
  }
  return _Parsed(f);
}

/// Validasi satu kategori tiket. Mengembalikan null bila tidak valid.
Map<String, Object?>? _parseTier(Object? t, {bool partial = false}) {
  if (t is! Map) return null;
  final b = t.map((k, v) => MapEntry(k.toString(), v));
  final out = <String, Object?>{};
  if (!partial || b.containsKey('name')) {
    final n = b['name'];
    if (n is! String || n.trim().isEmpty || n.length > 40) return null;
    out['name'] = n.trim();
  }
  if (b.containsKey('description')) {
    final d = b['description'];
    if (d != null && (d is! String || d.length > 200)) return null;
    out['description'] = (d is String && d.trim().isNotEmpty) ? d.trim() : null;
  }
  if (!partial || b.containsKey('price_idr')) {
    final p = _int(b['price_idr']);
    if (p == null || p < 0) return null;
    out['price_idr'] = p;
  }
  if (!partial || b.containsKey('stock')) {
    final s = _int(b['stock']);
    if (s == null || s < 0) return null;
    out['stock'] = s;
  }
  if (b.containsKey('sort_order')) {
    final o = _int(b['sort_order']);
    if (o == null) return null;
    out['sort_order'] = o;
  }
  return out;
}

/// events.price_idr = harga termurah, events.stock = jumlah stok semua kategori.
Future<void> _syncFromTiers(AppDb db, int eventId) async {
  final row = await db.one(
    'SELECT MIN(price_idr) AS p, COALESCE(SUM(stock),0) AS s, COUNT(*) AS n FROM ticket_tiers WHERE event_id=?',
    <Object?>[eventId],
  );
  if (row != null && (row['n'] as int) > 0) {
    await db.run('UPDATE events SET price_idr=?, stock=? WHERE id=?', <Object?>[row['p'], row['s'], eventId]);
  }
}

const String _eventStatsSql = '''SELECT e.*,
  (SELECT COUNT(*) FROM tickets t WHERE t.event_id = e.id) AS tickets_sold,
  (SELECT COUNT(*) FROM tickets t WHERE t.event_id = e.id AND t.used_at IS NOT NULL) AS checked_in
  FROM events e''';

Future<List<Map<String, Object?>>> _withTiers(AppDb db, List<Map<String, Object?>> events) async {
  final tiers = await db.all('SELECT * FROM ticket_tiers ORDER BY sort_order, id');
  return events.map((e) {
    return <String, Object?>{
      ...e,
      'tiers': tiers.where((t) => t['event_id'] == e['id']).toList(),
    };
  }).toList();
}

Future<Map<String, Object?>?> _eventDetail(AppDb db, int id) async {
  final e = await db.one('$_eventStatsSql WHERE e.id=?', <Object?>[id]);
  return e == null ? null : (await _withTiers(db, <Map<String, Object?>>[e])).first;
}

/// Pemeriksaan tiket (dipakai verifikasi dan check-in).
/// status: not_found | invalid_chain | wrong_event | event_cancelled | already_used | valid
Future<Map<String, Object?>> _inspectTicket(AppDb db, String code, {int? eventId}) async {
  final t = await db.one(
    '''SELECT t.ticket_code, t.event_id, t.used_at, t.checked_in_by,
              e.title AS event_title, e.start_time_utc, e.status AS event_status,
              u.name AS owner_name, u.email AS owner_email, tr.tier_name,
              cb.name AS checked_in_by_name
       FROM tickets t
       JOIN events e ON e.id = t.event_id
       JOIN users u ON u.id = t.user_id
       LEFT JOIN transactions tr ON tr.order_id = t.order_id
       LEFT JOIN users cb ON cb.id = t.checked_in_by
       WHERE t.ticket_code = ?''',
    <Object?>[code],
  );
  if (t == null) {
    return <String, Object?>{'status': 'not_found', 'message': 'Ticket not found. It may be fake.', 'ticket': null};
  }
  final block = await db.one('SELECT idx, hash FROM blocks WHERE ticket_code=?', <Object?>[code]);
  final chain = await verifyChain(db);
  final base = <String, Object?>{
    'ticket': t,
    'block_index': block?['idx'],
    'chain_valid': chain.valid,
    'broken_at': chain.valid ? null : chain.brokenAt,
  };
  String status;
  String message;
  if (block == null || !chain.valid) {
    status = 'invalid_chain';
    message = block == null ? 'Ticket is not registered on the blockchain.' : 'Blockchain integrity check failed.';
  } else if (eventId != null && t['event_id'] != eventId) {
    status = 'wrong_event';
    message = 'This ticket is for another event: ${t['event_title']}.';
  } else if (t['event_status'] == 'cancelled') {
    status = 'event_cancelled';
    message = 'This event has been cancelled.';
  } else if (t['used_at'] != null) {
    status = 'already_used';
    message = 'Ticket already used at ${t['used_at']}${t['checked_in_by_name'] != null ? ' (checked in by ${t['checked_in_by_name']})' : ''}.';
  } else {
    status = 'valid';
    message = 'Valid ticket.';
  }
  return <String, Object?>{...base, 'status': status, 'message': message};
}

void registerAdmin(Router r, AppDb db) {
  void get(String p, Handler h) => r.get(p, _adminOnly(db, h), auth: true);
  void post(String p, Handler h) => r.post(p, _adminOnly(db, h), auth: true);
  void put(String p, Handler h) => r.put(p, _adminOnly(db, h), auth: true);
  void del(String p, Handler h) => r.delete(p, _adminOnly(db, h), auth: true);

  Future<void> log(Ctx c, String action, String target, [String? detail]) async {
    await db.run(
      'INSERT INTO admin_logs(admin_id,action,target,detail) VALUES(?,?,?,?)',
      <Object?>[c.userId, action, target, detail],
    );
  }

  int? pid(Ctx c) => int.tryParse(c.params['id'] ?? '');

  Future<void> bad(Ctx c, String message, [int status = 400]) => c.json(status, <String, Object?>{'message': message});

  // Cek akses admin (dipakai app admin setelah login)
  get('/api/admin/me', (c) async {
    final u = await db.one('SELECT id,name,email,role FROM users WHERE id=?', <Object?>[c.userId]);
    await c.json(200, u);
  });

  // ---------------- Dashboard ----------------
  get('/api/admin/dashboard', (c) async {
    final nowIso = isoMs(DateTime.now());
    final since = sqlTs(DateTime.now().toUtc().subtract(const Duration(days: 14)));
    final revenue = (await db.one("SELECT COALESCE(SUM(gross_amount),0) AS v FROM transactions WHERE status='paid'"))!['v'];
    await c.json(200, <String, Object?>{
      'revenue_idr': revenue,
      'tickets_sold': (await db.one('SELECT COUNT(*) AS n FROM tickets'))!['n'],
      'tickets_checked_in': (await db.one('SELECT COUNT(*) AS n FROM tickets WHERE used_at IS NOT NULL'))!['n'],
      'users': (await db.one("SELECT COUNT(*) AS n FROM users WHERE role='user'"))!['n'],
      'active_events': (await db.one(
        "SELECT COUNT(*) AS n FROM events WHERE status='active' AND end_time_utc > ?",
        <Object?>[nowIso],
      ))!['n'],
      'orders_by_status': await db.all('SELECT status, COUNT(*) AS n FROM transactions GROUP BY status'),
      'top_events': await db.all(
        '''SELECT e.id, e.title, e.artist, COUNT(t.id) AS tickets_sold
           FROM events e LEFT JOIN tickets t ON t.event_id = e.id
           GROUP BY e.id ORDER BY tickets_sold DESC, e.id LIMIT 5''',
      ),
      'sales_by_day': await db.all(
        '''SELECT substr(created_at,1,10) AS day, COUNT(*) AS orders, SUM(gross_amount) AS revenue
           FROM transactions WHERE status='paid' AND created_at >= ?
           GROUP BY substr(created_at,1,10) ORDER BY day''',
        <Object?>[since],
      ),
      'low_stock': await db.all(
        "SELECT id, title, stock FROM events WHERE status='active' AND stock <= 20 AND end_time_utc > ? ORDER BY stock, id",
        <Object?>[nowIso],
      ),
    });
  });

  // ---------------- Event ----------------
  get('/api/admin/events', (c) async {
    final status = c.query['status'];
    final q = c.query['q'] ?? '';
    var sql = '$_eventStatsSql WHERE (e.title LIKE ? OR e.artist LIKE ?)';
    final params = <Object?>['%$q%', '%$q%'];
    if (status != null && _eventStatuses.contains(status)) {
      sql += ' AND e.status=?';
      params.add(status);
    }
    await c.json(200, await _withTiers(db, await db.all('$sql ORDER BY e.start_time_utc DESC, e.id DESC', params)));
  });

  get('/api/admin/events/:id', (c) async {
    final eid = pid(c);
    final e = eid == null ? null : await _eventDetail(db, eid);
    if (e == null) return bad(c, 'Event not found', 404);
    await c.json(200, e);
  });

  post('/api/admin/events', (c) async {
    final b = c.bodyMap;
    final p = _parseEvent(b, create: true);
    if (p.error != null) return bad(c, p.error!);
    final f = p.fields;
    if (!DateTime.parse(f['end_time_utc'] as String).isAfter(DateTime.parse(f['start_time_utc'] as String))) {
      return bad(c, 'end_time_utc must be after start_time_utc');
    }

    final tiers = <Map<String, Object?>>[];
    final tiersIn = b['tiers'];
    if (tiersIn is List && tiersIn.isNotEmpty) {
      for (final t in tiersIn) {
        final parsed = _parseTier(t);
        if (parsed == null) return bad(c, 'Invalid ticket category (name, price_idr >= 0, stock >= 0 are required)');
        tiers.add(parsed);
      }
      f['price_idr'] = tiers.map((t) => t['price_idr'] as int).reduce((a, b) => a < b ? a : b);
      f['stock'] = tiers.fold<int>(0, (a, t) => a + (t['stock'] as int));
    } else if (f['price_idr'] == null || f['stock'] == null) {
      return bad(c, 'Provide either "tiers" or both price_idr and stock');
    }

    final id = await db.transaction<int>((tx) async {
      final cols = f.keys.toList();
      final eventId = await tx.insert(
        'INSERT INTO events(${cols.join(',')}) VALUES(${List<String>.filled(cols.length, '?').join(',')})',
        cols.map((k) => f[k]).toList(),
      );
      var order = 0;
      for (final t in tiers) {
        await tx.run(
          'INSERT INTO ticket_tiers(event_id,name,description,price_idr,stock,sort_order) VALUES(?,?,?,?,?,?)',
          <Object?>[eventId, t['name'], t['description'], t['price_idr'], t['stock'], order++],
        );
      }
      return eventId;
    });
    await log(c, 'event.create', 'event:$id', f['title'] as String);
    await c.json(201, await _eventDetail(db, id));
  });

  put('/api/admin/events/:id', (c) async {
    final id = pid(c);
    final ev = id == null ? null : await db.one('SELECT * FROM events WHERE id=?', <Object?>[id]);
    if (id == null || ev == null) return bad(c, 'Event not found', 404);
    final p = _parseEvent(c.bodyMap, create: false);
    if (p.error != null) return bad(c, p.error!);
    final f = p.fields;
    final hasTiers = ((await db.one('SELECT COUNT(*) AS n FROM ticket_tiers WHERE event_id=?', <Object?>[id]))!['n'] as int) > 0;
    if (hasTiers) {
      f.remove('price_idr'); // harga & stok diturunkan dari kategori tiket
      f.remove('stock');
    }
    if (f.isEmpty) return bad(c, 'Nothing to update');
    final start = (f['start_time_utc'] ?? ev['start_time_utc']) as String;
    final end = (f['end_time_utc'] ?? ev['end_time_utc']) as String;
    if (!DateTime.parse(end).isAfter(DateTime.parse(start))) return bad(c, 'end_time_utc must be after start_time_utc');

    final cols = f.keys.toList();
    await db.transaction<void>((tx) async {
      await tx.run(
        'UPDATE events SET ${cols.map((k) => '$k=?').join(',')} WHERE id=?',
        <Object?>[...cols.map((k) => f[k]), id],
      );
      // Event dibatalkan -> beri tahu semua pembeli yang sudah membayar
      if (f['status'] == 'cancelled' && ev['status'] != 'cancelled') {
        await tx.run(
          "INSERT INTO notifications(user_id,title,body) SELECT DISTINCT user_id, CAST(? AS TEXT), CAST(? AS TEXT) FROM transactions WHERE event_id=? AND status='paid'",
          <Object?>['Event cancelled', '"${ev['title']}" has been cancelled. Please contact support for a refund.', id],
        );
      }
    });
    await log(c, 'event.update', 'event:$id', cols.join(','));
    await c.json(200, await _eventDetail(db, id));
  });

  del('/api/admin/events/:id', (c) async {
    final id = pid(c);
    final ev = id == null ? null : await db.one('SELECT id, title FROM events WHERE id=?', <Object?>[id]);
    if (id == null || ev == null) return bad(c, 'Event not found', 404);
    final orders = (await db.one('SELECT COUNT(*) AS n FROM transactions WHERE event_id=?', <Object?>[id]))!['n'] as int;
    if (orders > 0) {
      return bad(c, 'This event already has orders. Cancel it instead of deleting it.', 409);
    }
    await db.transaction<void>((tx) async {
      await tx.run('UPDATE emergency_alerts SET event_id=NULL WHERE event_id=?', <Object?>[id]);
      await tx.run('DELETE FROM ticket_tiers WHERE event_id=?', <Object?>[id]);
      await tx.run('DELETE FROM events WHERE id=?', <Object?>[id]);
    });
    await log(c, 'event.delete', 'event:$id', ev['title'] as String);
    await c.json(200, <String, Object?>{'message': 'Event deleted'});
  });

  // ---------------- Kategori tiket ----------------
  post('/api/admin/events/:id/tiers', (c) async {
    final id = pid(c);
    if (id == null || await db.one('SELECT id FROM events WHERE id=?', <Object?>[id]) == null) return bad(c, 'Event not found', 404);
    final t = _parseTier(c.bodyMap);
    if (t == null) return bad(c, 'Invalid ticket category (name, price_idr >= 0, stock >= 0 are required)');
    final next = (await db.one('SELECT COALESCE(MAX(sort_order),-1)+1 AS n FROM ticket_tiers WHERE event_id=?', <Object?>[id]))!['n'];
    await db.transaction<void>((tx) async {
      await tx.run(
        'INSERT INTO ticket_tiers(event_id,name,description,price_idr,stock,sort_order) VALUES(?,?,?,?,?,?)',
        <Object?>[id, t['name'], t['description'], t['price_idr'], t['stock'], t['sort_order'] ?? next],
      );
      await _syncFromTiers(tx, id);
    });
    await log(c, 'tier.create', 'event:$id', t['name'] as String);
    await c.json(201, await _eventDetail(db, id));
  });

  put('/api/admin/tiers/:id', (c) async {
    final tid = pid(c);
    final tier = tid == null ? null : await db.one('SELECT * FROM ticket_tiers WHERE id=?', <Object?>[tid]);
    if (tier == null) return bad(c, 'Ticket category not found', 404);
    final t = _parseTier(c.bodyMap, partial: true);
    if (t == null || t.isEmpty) return bad(c, 'Invalid or empty ticket category data');
    final cols = t.keys.toList();
    await db.transaction<void>((tx) async {
      await tx.run(
        'UPDATE ticket_tiers SET ${cols.map((k) => '$k=?').join(',')} WHERE id=?',
        <Object?>[...cols.map((k) => t[k]), tier['id']],
      );
      await _syncFromTiers(tx, (tier['event_id'] as num).toInt());
    });
    await log(c, 'tier.update', 'tier:${tier['id']}', cols.join(','));
    await c.json(200, await _eventDetail(db, (tier['event_id'] as num).toInt()));
  });

  del('/api/admin/tiers/:id', (c) async {
    final tid = pid(c);
    final tier = tid == null ? null : await db.one('SELECT * FROM ticket_tiers WHERE id=?', <Object?>[tid]);
    if (tier == null) return bad(c, 'Ticket category not found', 404);
    final used = (await db.one('SELECT COUNT(*) AS n FROM transactions WHERE tier_id=?', <Object?>[tier['id']]))!['n'] as int;
    if (used > 0) return bad(c, 'This category already has orders. Set its stock to 0 instead of deleting it.', 409);
    await db.transaction<void>((tx) async {
      await tx.run('DELETE FROM ticket_tiers WHERE id=?', <Object?>[tier['id']]);
      await _syncFromTiers(tx, (tier['event_id'] as num).toInt());
    });
    await log(c, 'tier.delete', 'tier:${tier['id']}', tier['name'] as String);
    await c.json(200, await _eventDetail(db, (tier['event_id'] as num).toInt()));
  });

  // ---------------- Transaksi ----------------
  get('/api/admin/orders', (c) async {
    final status = c.query['status'];
    final q = c.query['q'] ?? '';
    var where = 'WHERE (tr.order_id LIKE ? OR u.email LIKE ? OR u.name LIKE ?)';
    final params = <Object?>['%$q%', '%$q%', '%$q%'];
    if (status != null && status.isNotEmpty) {
      where += ' AND tr.status=?';
      params.add(status);
    }
    const from = 'FROM transactions tr JOIN users u ON u.id = tr.user_id JOIN events e ON e.id = tr.event_id';
    final total = (await db.one('SELECT COUNT(*) AS n $from $where', params))!['n'];
    final items = await db.all(
      '''SELECT tr.order_id, tr.status, tr.qty, tr.gross_amount, tr.tier_name, tr.created_at,
                u.name AS user_name, u.email AS user_email, e.title AS event_title
         $from $where ORDER BY tr.created_at DESC, tr.order_id DESC LIMIT ? OFFSET ?''',
      <Object?>[...params, _limit(c), _offset(c)],
    );
    await c.json(200, <String, Object?>{'total': total, 'items': items});
  });

  // ---------------- User ----------------
  get('/api/admin/users', (c) async {
    final q = c.query['q'] ?? '';
    final rows = await db.all(
      '''SELECT u.id, u.name, u.email, u.role, u.created_at,
                (SELECT COUNT(*) FROM tickets t WHERE t.user_id = u.id) AS tickets,
                (SELECT COALESCE(SUM(gross_amount),0) FROM transactions tr
                   WHERE tr.user_id = u.id AND tr.status='paid') AS total_spent_idr
         FROM users u WHERE (u.name LIKE ? OR u.email LIKE ?)
         ORDER BY u.id DESC LIMIT ? OFFSET ?''',
      <Object?>['%$q%', '%$q%', _limit(c), _offset(c)],
    );
    await c.json(200, rows);
  });

  // ---------------- Promo ----------------
  get('/api/admin/promos', (c) async {
    await c.json(200, await db.all('SELECT code, description, discount_percent, active FROM promos ORDER BY code'));
  });

  post('/api/admin/promos', (c) async {
    final b = c.bodyMap;
    final code = (b['code'] ?? '').toString().trim().toUpperCase();
    final desc = b['description'];
    final pct = _int(b['discount_percent']);
    if (!RegExp(r'^[A-Z0-9_-]{3,20}$').hasMatch(code)) {
      return bad(c, 'Code must be 3-20 characters: letters, numbers, - or _');
    }
    if (desc is! String || desc.trim().isEmpty || desc.length > 120) return bad(c, 'Description is required (max 120 characters)');
    if (pct == null || pct < 1 || pct > 90) return bad(c, 'discount_percent must be a whole number from 1 to 90');
    if (await db.one('SELECT 1 AS x FROM promos WHERE code=?', <Object?>[code]) != null) {
      return bad(c, 'Promo code already exists', 409);
    }
    await db.run('INSERT INTO promos(code,description,discount_percent,active) VALUES(?,?,?,1)', <Object?>[code, desc.trim(), pct]);
    await log(c, 'promo.create', 'promo:$code', '$pct%');
    await c.json(201, await db.one('SELECT code, description, discount_percent, active FROM promos WHERE code=?', <Object?>[code]));
  });

  put('/api/admin/promos/:code', (c) async {
    final code = (c.params['code'] ?? '').toUpperCase();
    final p = await db.one('SELECT * FROM promos WHERE code=?', <Object?>[code]);
    if (p == null) return bad(c, 'Promo not found', 404);
    final b = c.bodyMap;
    final sets = <String>[];
    final vals = <Object?>[];
    if (b.containsKey('description')) {
      final d = b['description'];
      if (d is! String || d.trim().isEmpty || d.length > 120) return bad(c, 'Invalid description');
      sets.add('description=?');
      vals.add(d.trim());
    }
    if (b.containsKey('discount_percent')) {
      final pct = _int(b['discount_percent']);
      if (pct == null || pct < 1 || pct > 90) return bad(c, 'discount_percent must be a whole number from 1 to 90');
      sets.add('discount_percent=?');
      vals.add(pct);
    }
    if (b.containsKey('active')) {
      sets.add('active=?');
      vals.add((b['active'] == true || b['active'] == 1) ? 1 : 0);
    }
    if (sets.isEmpty) return bad(c, 'Nothing to update');
    await db.run('UPDATE promos SET ${sets.join(',')} WHERE code=?', <Object?>[...vals, code]);
    await log(c, 'promo.update', 'promo:$code', sets.map((s) => s.split('=').first).join(','));
    await c.json(200, await db.one('SELECT code, description, discount_percent, active FROM promos WHERE code=?', <Object?>[code]));
  });

  // ---------------- Tiket: verifikasi & check-in ----------------
  get('/api/admin/events/:id/tickets', (c) async {
    final rows = await db.all(
      '''SELECT t.ticket_code, t.used_at, u.name AS owner_name, u.email AS owner_email,
                tr.tier_name, cb.name AS checked_in_by_name
         FROM tickets t
         JOIN users u ON u.id = t.user_id
         LEFT JOIN transactions tr ON tr.order_id = t.order_id
         LEFT JOIN users cb ON cb.id = t.checked_in_by
         WHERE t.event_id = ? ORDER BY t.id''',
      <Object?>[pid(c) ?? -1],
    );
    await c.json(200, rows);
  });

  // Cek keaslian tiket TANPA menandainya sudah dipakai
  post('/api/admin/tickets/verify', (c) async {
    final b = c.bodyMap;
    final code = (b['code'] ?? '').toString().trim().toUpperCase();
    if (code.isEmpty) return bad(c, 'Ticket code is required');
    await c.json(200, await _inspectTicket(db, code, eventId: _int(b['event_id'])));
  });

  // Check-in di pintu masuk: lolos hanya bila tiket asli, event benar, dan belum dipakai
  post('/api/admin/tickets/check-in', (c) async {
    final b = c.bodyMap;
    final code = (b['code'] ?? '').toString().trim().toUpperCase();
    if (code.isEmpty) return bad(c, 'Ticket code is required');
    final result = await _inspectTicket(db, code, eventId: _int(b['event_id']));
    if (result['status'] != 'valid') {
      await c.json(200, <String, Object?>{...result, 'ok': false});
      return;
    }
    final now = isoMs(DateTime.now());
    // "AND used_at IS NULL" mencegah dua petugas men-scan tiket yang sama bersamaan
    final changed = (await db.run(
      'UPDATE tickets SET used_at=?, checked_in_by=? WHERE ticket_code=? AND used_at IS NULL',
      <Object?>[now, c.userId, code],
    )).changes;
    if (changed != 1) {
      await c.json(200, <String, Object?>{...await _inspectTicket(db, code, eventId: _int(b['event_id'])), 'ok': false});
      return;
    }
    await log(c, 'ticket.checkin', 'ticket:$code', (result['ticket'] as Map)['event_title'] as String);
    await c.json(200, <String, Object?>{
      ...await _inspectTicket(db, code, eventId: _int(b['event_id'])),
      'status': 'checked_in',
      'message': 'Check-in successful. Welcome!',
      'ok': true,
    });
  });

  // ---------------- Notifikasi broadcast ----------------
  post('/api/admin/broadcast', (c) async {
    final b = c.bodyMap;
    final title = b['title'];
    final body = b['body'];
    if (title is! String || title.trim().isEmpty || title.length > 80) return bad(c, 'Title is required (max 80 characters)');
    if (body is! String || body.trim().isEmpty || body.length > 300) return bad(c, 'Body is required (max 300 characters)');
    final changes = (await db.run(
      'INSERT INTO notifications(user_id,title,body) SELECT id, CAST(? AS TEXT), CAST(? AS TEXT) FROM users',
      <Object?>[title.trim(), body.trim()],
    )).changes;
    await log(c, 'broadcast.send', 'users:$changes', title.trim());
    await c.json(201, <String, Object?>{'sent_to': changes});
  });

  // ---------------- Darurat, feedback, blockchain, log ----------------
  get('/api/admin/emergency', (c) async {
    await c.json(
      200,
      await db.all(
        '''SELECT a.id, a.ticket_code, a.latitude, a.longitude, a.created_at,
                  u.name AS user_name, u.email AS user_email, e.title AS event_title
           FROM emergency_alerts a
           JOIN users u ON u.id = a.user_id
           LEFT JOIN events e ON e.id = a.event_id
           ORDER BY a.id DESC LIMIT ?''',
        <Object?>[_limit(c, def: 100)],
      ),
    );
  });

  get('/api/admin/feedback', (c) async {
    await c.json(
      200,
      await db.all(
        '''SELECT f.id, f.rating, f.message, f.created_at, u.name AS user_name, u.email AS user_email
           FROM course_feedback f JOIN users u ON u.id = f.user_id
           ORDER BY f.id DESC LIMIT ?''',
        <Object?>[_limit(c, def: 100)],
      ),
    );
  });

  get('/api/admin/blockchain', (c) async {
    final chain = await verifyChain(db);
    await c.json(200, <String, Object?>{
      'valid': chain.valid,
      'broken_at': chain.valid ? null : chain.brokenAt,
      'length': (await db.one('SELECT COUNT(*) AS n FROM blocks'))!['n'],
      'blocks': await db.all('SELECT * FROM blocks ORDER BY idx DESC LIMIT ?', <Object?>[_limit(c, def: 50)]),
    });
  });

  get('/api/admin/logs', (c) async {
    await c.json(
      200,
      await db.all(
        '''SELECT l.id, l.action, l.target, l.detail, l.created_at, u.name AS admin_name
           FROM admin_logs l JOIN users u ON u.id = l.admin_id
           ORDER BY l.id DESC LIMIT ?''',
        <Object?>[_limit(c, def: 100)],
      ),
    );
  });
}
