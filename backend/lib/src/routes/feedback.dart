import '../db.dart';
import '../util.dart';
import '../web.dart';

/// Validasi rating (1-5) dan pesan (3-1000 karakter). Mengembalikan pesan error, atau null bila valid.
String? _validate(Map<String, dynamic> b) {
  final rating = numOf(b['rating']);
  if (rating == null || !isWhole(rating) || rating < 1 || rating > 5) return 'Rating must be 1-5';
  final message = b['message'];
  if (message is! String || message.trim().length < 3 || message.length > 1000) {
    return 'Message must be 3-1000 characters';
  }
  return null;
}

// Pesan & kesan untuk mata kuliah
void registerFeedback(Router r, AppDb db) {
  r.post('/api/feedback', (c) async {
    final b = c.bodyMap;
    final err = _validate(b);
    if (err != null) {
      await c.json(400, <String, Object?>{'message': err});
      return;
    }
    final newId = await db.insert(
      'INSERT INTO course_feedback(user_id,rating,message) VALUES(?,?,?)',
      <Object?>[c.userId, numOf(b['rating'])!.toInt(), (b['message'] as String).trim()],
    );
    await c.json(201, await db.one('SELECT * FROM course_feedback WHERE id=?', <Object?>[newId]));
  }, auth: true);

  // Ubah kesan & pesan milik sendiri (dipakai kartu "Kesan & Pesan" di profil)
  r.put('/api/feedback/:id', (c) async {
    final id = int.tryParse(c.params['id'] ?? '');
    final own = id == null
        ? null
        : await db.one('SELECT id FROM course_feedback WHERE id=? AND user_id=?', <Object?>[id, c.userId]);
    if (own == null) {
      await c.json(404, <String, Object?>{'message': 'Feedback not found'});
      return;
    }
    final b = c.bodyMap;
    final err = _validate(b);
    if (err != null) {
      await c.json(400, <String, Object?>{'message': err});
      return;
    }
    await db.run(
      'UPDATE course_feedback SET rating=?, message=? WHERE id=? AND user_id=?',
      <Object?>[numOf(b['rating'])!.toInt(), (b['message'] as String).trim(), id, c.userId],
    );
    await c.json(200, await db.one('SELECT * FROM course_feedback WHERE id=?', <Object?>[id]));
  }, auth: true);

  r.get('/api/feedback', (c) async {
    await c.json(
      200,
      await db.all('SELECT * FROM course_feedback WHERE user_id=? ORDER BY id DESC LIMIT 50', <Object?>[c.userId]),
    );
  }, auth: true);
}
