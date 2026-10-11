import '../db.dart';
import '../web.dart';

void registerPromos(Router r, AppDb db) {
  r.get('/api/promos', (c) async {
    await c.json(200, db.all('SELECT code, description, discount_percent FROM promos WHERE active=1'));
  });

  r.get('/api/promos/validate', (c) async {
    final code = (c.query['code'] ?? '').trim().toUpperCase();
    final p = db.one(
      'SELECT code, description, discount_percent FROM promos WHERE code=? AND active=1',
      <Object?>[code],
    );
    if (p == null) {
      await c.json(404, <String, Object?>{'message': 'Invalid promo code'});
      return;
    }
    await c.json(200, p);
  });
}
