import '../db.dart';
import '../util.dart';
import '../web.dart';

// Pesan & kesan untuk mata kuliah
void registerFeedback(Router r, AppDb db) {
  r.post('/api/feedback', (c) async {
    final b = c.bodyMap;
    final rating = numOf(b['rating']);
    if (rating == null || !isWhole(rating) || rating < 1 || rating > 5) {
      await c.json(400, <String, Object?>{'message': 'Rating must be 1-5'});
      return;
    }
    final message = b['message'];
    if (message is! String || message.trim().length < 3 || message.length > 1000) {
      await c.json(400, <String, Object?>{'message': 'Message must be 3-1000 characters'});
      return;
    }
    final info = db.run(
      'INSERT INTO course_feedback(user_id,rating,message) VALUES(?,?,?)',
      <Object?>[c.userId, rating.toInt(), message.trim()],
    );
    await c.json(201, db.one('SELECT * FROM course_feedback WHERE id=?', <Object?>[info.lastInsertId]));
  }, auth: true);

  r.get('/api/feedback', (c) async {
    await c.json(
      200,
      db.all('SELECT * FROM course_feedback WHERE user_id=? ORDER BY id DESC LIMIT 50', <Object?>[c.userId]),
    );
  }, auth: true);
}
