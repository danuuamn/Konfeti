import 'dart:convert';

import 'package:crypto/crypto.dart';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _hmac(String secret, String data) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(data)).bytes;

/// Membuat JWT HS256 (format sama dengan paket jsonwebtoken di Node.js). Berlaku 7 hari.
String signJwt(int userId, String secret) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final header = _b64(utf8.encode(jsonEncode(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'})));
  final payload = _b64(utf8.encode(jsonEncode(<String, Object?>{
    'id': userId,
    'iat': now,
    'exp': now + 7 * 24 * 3600,
  })));
  final signature = _b64(_hmac(secret, '$header.$payload'));
  return '$header.$payload.$signature';
}

/// Mengembalikan id user bila token valid dan belum kedaluwarsa, selain itu null.
int? verifyJwt(String token, String secret) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final header = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
    if (header is! Map || header['alg'] != 'HS256') return null;

    final expected = _hmac(secret, '${parts[0]}.${parts[1]}');
    final given = base64Url.decode(base64Url.normalize(parts[2]));
    if (expected.length != given.length) return null;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ given[i];
    }
    if (diff != 0) return null;

    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (payload is! Map) return null;
    final exp = payload['exp'];
    if (exp is num && DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp.toInt()) return null;
    final id = payload['id'];
    if (id is! num) return null;
    return id.toInt();
  } catch (_) {
    return null;
  }
}
