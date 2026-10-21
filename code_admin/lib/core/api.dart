import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Satu pintu untuk semua request. Token dipasang otomatis; 401 memicu [onUnauthorized].
class Api {
  Api._();
  static final Api instance = Api._();

  String? token;
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, String?>? q]) {
    final clean = <String, String>{};
    q?.forEach((k, v) {
      if (v != null && v.isNotEmpty) clean[k] = v;
    });
    final base = Uri.parse(AppConfig.apiBase);
    return base.replace(path: path, queryParameters: clean.isEmpty ? null : clean);
  }

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(Future<http.Response> Function() call, {bool authed = true}) async {
    http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(0, 'Server tidak merespons. Cek koneksi dan alamat API.');
    } catch (_) {
      throw ApiException(0, 'Tidak bisa terhubung ke server (${AppConfig.apiBase}).');
    }
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final msg = body is Map && body['message'] is String ? body['message'] as String : 'Terjadi kesalahan (${res.statusCode}).';
    if (res.statusCode == 401 && authed) onUnauthorized?.call();
    throw ApiException(res.statusCode, msg);
  }

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? <String, Object?>{})));

  Future<dynamic> put(String path, Object body) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  /// Login tidak boleh memicu auto-logout 401.
  Future<dynamic> login(String email, String password) => _send(
        () => http.post(_uri('/api/auth/login'),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{'email': email, 'password': password})),
        authed: false,
      );
}
