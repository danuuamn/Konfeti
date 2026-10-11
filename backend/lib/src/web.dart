import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'env.dart';
import 'jwt.dart';

typedef Handler = FutureOr<void> Function(Ctx c);

/// Konteks satu request: parameter path, query, body JSON, dan helper untuk membalas.
class Ctx {
  Ctx(this.request, this.params, this.query, this.body);

  final HttpRequest request;
  final Map<String, String> params;
  final Map<String, String> query;
  final Object? body;
  int userId = 0;

  /// Body JSON sebagai Map (kosong bila tidak ada / bukan objek).
  Map<String, dynamic> get bodyMap {
    final b = body;
    if (b is Map) {
      return b.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Future<void> json(int status, Object? data) async {
    final bytes = utf8.encode(jsonEncode(data));
    final res = request.response;
    res.statusCode = status;
    res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  /// Balasan tanpa body.
  Future<void> empty(int status) async {
    final res = request.response;
    res.statusCode = status;
    res.headers.contentLength = 0;
    await res.close();
  }
}

class Route {
  Route(this.method, this.segments, this.handler, this.auth);
  final String method;
  final List<String> segments;
  final Handler handler;
  final bool auth;
}

class Router {
  final List<Route> routes = <Route>[];

  void get(String path, Handler h, {bool auth = false}) => _add('GET', path, h, auth);
  void post(String path, Handler h, {bool auth = false}) => _add('POST', path, h, auth);
  void put(String path, Handler h, {bool auth = false}) => _add('PUT', path, h, auth);

  void _add(String method, String path, Handler h, bool auth) {
    routes.add(Route(method, _split(path), h, auth));
  }

  static List<String> _split(String p) => p.split('/').where((s) => s.isNotEmpty).toList();

  /// Cari route yang cocok; parameter `:nama` dimasukkan ke [params]. Urutan pendaftaran menentukan prioritas.
  Route? match(String method, String path, Map<String, String> params) {
    final parts = _split(path);
    for (final r in routes) {
      if (r.method != method || r.segments.length != parts.length) continue;
      final found = <String, String>{};
      var ok = true;
      for (var i = 0; i < parts.length; i++) {
        final seg = r.segments[i];
        if (seg.startsWith(':')) {
          found[seg.substring(1)] = Uri.decodeComponent(parts[i]);
        } else if (seg != parts[i]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        params.addAll(found);
        return r;
      }
    }
    return null;
  }
}

class _Bucket {
  _Bucket(this.reset) : count = 1;
  DateTime reset;
  int count;
}

/// Pembatas laju sederhana (per alamat IP, jendela tetap).
class RateLimiter {
  RateLimiter(this.window, this.max);

  final Duration window;
  final int max;
  final Map<String, _Bucket> _buckets = <String, _Bucket>{};

  bool allow(String key) {
    final now = DateTime.now();
    if (_buckets.length > 5000) {
      _buckets.removeWhere((k, b) => now.isAfter(b.reset));
    }
    final b = _buckets[key];
    if (b == null || now.isAfter(b.reset)) {
      _buckets[key] = _Bucket(now.add(window));
      return true;
    }
    b.count++;
    return b.count <= max;
  }
}

String? _bearer(HttpRequest req) {
  final h = req.headers.value('authorization');
  if (h == null) return null;
  return h.replaceFirst('Bearer ', '');
}

const Map<String, String> _mimeTypes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// Server HTTP: header keamanan, CORS, rate limit, parsing JSON, routing, file statis /uploads.
class AppServer {
  AppServer(this.router);

  final Router router;
  final RateLimiter _authLimiter = RateLimiter(const Duration(minutes: 15), 200);
  final RateLimiter _chatLimiter = RateLimiter(const Duration(minutes: 1), 20);

  static const int _maxBody = 6 * 1024 * 1024;

  Future<void> serve(int port) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Konfeti API running on http://localhost:$port');
    await for (final req in server) {
      // setiap request ditangani sendiri; error satu request tidak mematikan server
      unawaited(_handle(req));
    }
  }

  void _commonHeaders(HttpResponse res, HttpRequest req) {
    res.headers.set('X-Content-Type-Options', 'nosniff');
    res.headers.set('X-Frame-Options', 'SAMEORIGIN');
    res.headers.set('Referrer-Policy', 'no-referrer');
    res.headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
    res.headers.set('Access-Control-Allow-Origin', '*');
  }

  Future<void> _handle(HttpRequest req) async {
    final started = DateTime.now();
    final res = req.response;
    try {
      _commonHeaders(res, req);

      // CORS preflight
      if (req.method == 'OPTIONS') {
        res.headers.set('Access-Control-Allow-Methods', 'GET,HEAD,PUT,PATCH,POST,DELETE');
        final asked = req.headers.value('access-control-request-headers');
        res.headers.set('Access-Control-Allow-Headers', asked ?? 'Content-Type, Authorization');
        res.statusCode = 204;
        res.headers.contentLength = 0;
        await res.close();
        return;
      }

      final path = req.uri.path;
      final ip = req.connectionInfo?.remoteAddress.address ?? 'unknown';

      if (path.startsWith('/api/auth') && !_authLimiter.allow(ip)) {
        await _plain(req, 429, 'Too many requests, please try again later.');
        return;
      }
      if (path.startsWith('/api/chat') && !_chatLimiter.allow(ip)) {
        await _plain(req, 429, 'Too many requests, please try again later.');
        return;
      }

      if (await _serveUpload(req, path)) return;

      // Baca body (maks 6 MB) dan parse bila JSON
      Object? body;
      if (req.method == 'POST' || req.method == 'PUT' || req.method == 'PATCH') {
        final bytes = await _readBody(req);
        if (bytes == null) {
          await _jsonError(req, 413, 'Request body too large');
          return;
        }
        final mime = req.headers.contentType?.mimeType ?? '';
        if (bytes.isNotEmpty && mime.contains('json')) {
          try {
            body = jsonDecode(utf8.decode(bytes));
          } catch (_) {
            await _jsonError(req, 400, 'Invalid JSON body');
            return;
          }
        }
      }

      final params = <String, String>{};
      Route? route;
      try {
        route = router.match(req.method, path, params);
      } catch (_) {
        await _jsonError(req, 400, 'Bad request');
        return;
      }
      if (route == null) {
        await _jsonError(req, 404, 'Not found');
        return;
      }

      final ctx = Ctx(req, params, req.uri.queryParameters, body);

      if (route.auth) {
        final token = _bearer(req) ?? '';
        final id = verifyJwt(token, Env.get('JWT_SECRET'));
        if (id == null) {
          await ctx.json(401, <String, Object?>{'message': 'Unauthorized'});
          return;
        }
        ctx.userId = id;
      }

      await route.handler(ctx);
    } catch (e, st) {
      stderr.writeln('Unhandled error on ${req.method} ${req.uri.path}: $e\n$st');
      try {
        await _jsonError(req, 500, 'Internal server error');
      } catch (_) {}
    } finally {
      final ms = DateTime.now().difference(started).inMilliseconds;
      print('${req.method} ${req.uri.path} -> ${res.statusCode} (${ms}ms)');
    }
  }

  Future<List<int>?> _readBody(HttpRequest req) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req) {
      builder.add(chunk);
      if (builder.length > _maxBody) return null;
    }
    return builder.takeBytes();
  }

  Future<void> _jsonError(HttpRequest req, int status, String message) async {
    final bytes = utf8.encode(jsonEncode(<String, Object?>{'message': message}));
    final res = req.response;
    res.statusCode = status;
    res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  Future<void> _plain(HttpRequest req, int status, String text) async {
    final bytes = utf8.encode(text);
    final res = req.response;
    res.statusCode = status;
    res.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  /// Melayani file di folder ./uploads (foto profil).
  Future<bool> _serveUpload(HttpRequest req, String path) async {
    if (req.method != 'GET' && req.method != 'HEAD') return false;
    if (!path.startsWith('/uploads/')) return false;
    String rel;
    try {
      rel = Uri.decodeComponent(path.substring('/uploads/'.length));
    } catch (_) {
      return false;
    }
    if (rel.isEmpty || rel.contains('..') || rel.contains('\\') || rel.startsWith('/')) return false;
    final root = '${Directory.current.path}${Platform.pathSeparator}uploads';
    final file = File('$root${Platform.pathSeparator}$rel');
    if (!await file.exists()) return false;

    final dot = rel.lastIndexOf('.');
    final ext = dot >= 0 ? rel.substring(dot + 1).toLowerCase() : '';
    final res = req.response;
    res.statusCode = 200;
    res.headers.contentType = ContentType.parse(_mimeTypes[ext] ?? 'application/octet-stream');
    res.headers.contentLength = await file.length();
    if (req.method == 'HEAD') {
      await res.close();
    } else {
      await res.addStream(file.openRead());
      await res.close();
    }
    return true;
  }
}
