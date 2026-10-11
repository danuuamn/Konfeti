import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Klien HTTP tunggal. Token JWT disuntik otomatis ke header Authorization.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? token;

  /// Dipanggil saat server membalas 401 (token kedaluwarsa/tidak valid).
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('${AppConfig.apiBase}$path');
    return (query == null || query.isEmpty) ? u : u.replace(queryParameters: query);
  }

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) => _send(() =>
      http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? <String, Object?>{})));

  Future<dynamic> put(String path, Object body) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(0, 'Request timed out. Please try again.');
    } on SocketException {
      throw ApiException(0, 'Cannot reach the server. Check your connection.');
    } on http.ClientException {
      throw ApiException(0, 'Cannot reach the server. Check your connection.');
    }

    dynamic body;
    if (res.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        body = utf8.decode(res.bodyBytes, allowMalformed: true); // mis. 429 teks biasa
      }
    }

    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      final msg = body is Map && body['message'] != null
          ? body['message'].toString()
          : (body is String && body.isNotEmpty ? body : 'Error ${res.statusCode}');
      throw ApiException(res.statusCode, msg);
    }
    return body;
  }
}
