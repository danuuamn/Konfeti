import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';

import '../db.dart';
import '../env.dart';
import '../jwt.dart';
import '../web.dart';

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
bool _emailOk(Object? e) => e is String && _emailRe.hasMatch(e);

Map<String, Object?> _publicUser(Map<String, Object?> u) => <String, Object?>{
      'id': u['id'],
      'name': u['name'],
      'email': u['email'],
      'avatar_url': u['avatar_url'],
    };

/// Hash bcrypt di isolate terpisah supaya server tidak terhenti selama ~0,3 detik.
Future<String> _hashPassword(String password) =>
    Isolate.run<String>(() => BCrypt.hashpw(password, BCrypt.gensalt()));

/// Cek password. Hash dari bcryptjs/Node berawalan $2b$; algoritmanya sama dengan $2a$.
Future<bool> _checkPassword(String password, String hash) {
  var h = hash;
  if (h.startsWith(r'$2b$') || h.startsWith(r'$2y$')) {
    h = r'$2a$' + h.substring(4);
  }
  final normalized = h;
  return Isolate.run<bool>(() {
    try {
      return BCrypt.checkpw(password, normalized);
    } catch (_) {
      return false;
    }
  });
}

Map<String, Object?>? _userById(AppDb db, int id) =>
    db.one('SELECT id,name,email,avatar_url FROM users WHERE id=?', <Object?>[id]);

/// Membersihkan base64 agar mirip perilaku Buffer.from(..., 'base64') di Node (longgar).
List<int>? _decodeBase64(String input) {
  var s = input.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '');
  s = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
  s = s.replaceAll(RegExp(r'=+$'), '');
  final rem = s.length % 4;
  if (rem == 1) return null;
  if (rem == 2) s += '==';
  if (rem == 3) s += '=';
  try {
    return base64Decode(s);
  } on FormatException {
    return null;
  }
}

void registerAuth(Router r, AppDb db) {
  r.post('/api/auth/register', (c) async {
    final b = c.bodyMap;
    final name = b['name'];
    final email = b['email'];
    final password = b['password'];
    if (name is! String || name.trim().isEmpty || !_emailOk(email) || password is! String || password.length < 8) {
      await c.json(400, <String, Object?>{'message': 'Invalid input (name, valid email, password min 8 chars)'});
      return;
    }
    final emailStr = email as String;
    if (db.one('SELECT 1 AS x FROM users WHERE email=?', <Object?>[emailStr]) != null) {
      await c.json(409, <String, Object?>{'message': 'Email already registered'});
      return;
    }
    final hash = await _hashPassword(password);
    final info = db.run(
      'INSERT INTO users(name,email,password_hash) VALUES(?,?,?)',
      <Object?>[name.trim(), emailStr, hash],
    );
    final id = info.lastInsertId;
    db.run('INSERT INTO notifications(user_id,title,body) VALUES(?,?,?)', <Object?>[
      id,
      'Welcome to Konfeti!',
      'Use promo code KONFETI10 to get 10% off your first ticket.',
    ]);
    await c.json(201, <String, Object?>{
      'token': signJwt(id, Env.get('JWT_SECRET')),
      'user': <String, Object?>{'id': id, 'name': name.trim(), 'email': emailStr, 'avatar_url': null},
    });
  });

  r.post('/api/auth/login', (c) async {
    final b = c.bodyMap;
    final email = (b['email'] ?? '').toString();
    final password = (b['password'] ?? '').toString();
    final u = db.one('SELECT * FROM users WHERE email=?', <Object?>[email]);
    if (u == null || !await _checkPassword(password, u['password_hash'] as String)) {
      await c.json(401, <String, Object?>{'message': 'Invalid email or password'});
      return;
    }
    await c.json(200, <String, Object?>{
      'token': signJwt(u['id'] as int, Env.get('JWT_SECRET')),
      'user': _publicUser(u),
    });
  });

  r.get('/api/auth/me', (c) async {
    final u = _userById(db, c.userId);
    if (u == null) {
      await c.json(404, <String, Object?>{'message': 'User not found'});
      return;
    }
    await c.json(200, u);
  }, auth: true);

  // Ubah nama profil
  r.put('/api/auth/me', (c) async {
    final name = c.bodyMap['name'];
    if (name is! String || name.trim().length < 2 || name.length > 60) {
      await c.json(400, <String, Object?>{'message': 'Name must be 2-60 characters'});
      return;
    }
    db.run('UPDATE users SET name=? WHERE id=?', <Object?>[name.trim(), c.userId]);
    await c.json(200, _userById(db, c.userId));
  }, auth: true);

  // Upload foto profil (base64 JPEG/PNG, maks ~3 MB)
  r.post('/api/auth/me/avatar', (c) async {
    final raw = c.bodyMap['image_base64'];
    if (raw is! String || raw.isEmpty) {
      await c.json(400, <String, Object?>{'message': 'image_base64 is required'});
      return;
    }
    final buf = _decodeBase64(raw);
    if (buf == null || buf.length < 8 || buf.length > 3 * 1024 * 1024) {
      await c.json(400, <String, Object?>{'message': 'Image must be smaller than 3 MB'});
      return;
    }
    final isJpg = buf[0] == 0xff && buf[1] == 0xd8;
    final isPng = buf[0] == 0x89 && buf[1] == 0x50 && buf[2] == 0x4e && buf[3] == 0x47;
    if (!isJpg && !isPng) {
      await c.json(400, <String, Object?>{'message': 'Only JPEG or PNG images are allowed'});
      return;
    }
    final dir = Directory('${Directory.current.path}${Platform.pathSeparator}uploads${Platform.pathSeparator}avatars');
    await dir.create(recursive: true);
    final file = 'user-${c.userId}-${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}';
    await File('${dir.path}${Platform.pathSeparator}$file').writeAsBytes(buf);
    db.run('UPDATE users SET avatar_url=? WHERE id=?', <Object?>['/uploads/avatars/$file', c.userId]);
    await c.json(200, _userById(db, c.userId));
  }, auth: true);
}
