import '../db.dart';
import '../util.dart';
import '../web.dart';

// Dipanggil Flutter saat user mengguncang HP (accelerometer) di tiket yang sedang aktif
void registerEmergency(Router r, AppDb db) {
  r.post('/api/emergency', (c) async {
    final b = c.bodyMap;
    final rawLat = b['latitude'];
    final rawLon = b['longitude'];
    final double? lat = rawLat == null ? null : numOf(rawLat);
    final double? lon = rawLon == null ? null : numOf(rawLon);
    if ((rawLat != null && lat == null) || (rawLon != null && lon == null)) {
      await c.json(400, <String, Object?>{'message': 'Invalid coordinates'});
      return;
    }
    final eventId = b['event_id'];
    final evId = truthy(eventId) ? int.tryParse(eventId.toString()) : null;
    final ev = evId != null ? await db.one('SELECT id, title FROM events WHERE id=?', <Object?>[evId]) : null;
    final ticketCode = b['ticket_code'];

    // Alert yang tertunda karena HP offline mengirim waktu kejadian aslinya (occurred_at, ISO UTC).
    // Dipakai hanya bila masuk akal: tidak lebih dari 7 hari lalu dan tidak di masa depan.
    DateTime? occurred;
    if (truthy(b['occurred_at'])) {
      final t = DateTime.tryParse(b['occurred_at'].toString());
      final now = DateTime.now().toUtc();
      if (t != null && t.isAfter(now.subtract(const Duration(days: 7))) && !t.isAfter(now.add(const Duration(minutes: 5)))) {
        occurred = t.toUtc();
      }
    }

    final code = truthy(ticketCode) ? ticketCode.toString() : null;
    final newId = occurred == null
        ? await db.insert(
            'INSERT INTO emergency_alerts(user_id,event_id,ticket_code,latitude,longitude) VALUES(?,?,?,?,?)',
            <Object?>[c.userId, ev?['id'], code, lat, lon],
          )
        : await db.insert(
            'INSERT INTO emergency_alerts(user_id,event_id,ticket_code,latitude,longitude,created_at) VALUES(?,?,?,?,?,?)',
            <Object?>[c.userId, ev?['id'], code, lat, lon, sqlTs(occurred)],
          );
    await db.run('INSERT INTO notifications(user_id,title,body) VALUES(?,?,?)', <Object?>[
      c.userId,
      'Emergency alert sent',
      ev != null
          ? 'Event staff at "${ev['title']}" have been notified of your location.'
          : 'Event staff have been notified of your location.',
    ]);
    await c.json(201, <String, Object?>{'ok': true, 'id': newId});
  }, auth: true);

  r.get('/api/emergency', (c) async {
    await c.json(
      200,
      await db.all('SELECT * FROM emergency_alerts WHERE user_id=? ORDER BY id DESC LIMIT 20', <Object?>[c.userId]),
    );
  }, auth: true);
}
