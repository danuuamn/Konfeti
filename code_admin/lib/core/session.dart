import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

class AdminUser {
  AdminUser({required this.id, required this.name, required this.email});
  final int id;
  final String name;
  final String email;
}

class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _key = 'admin_token';
  final FlutterSecureStorage _store = const FlutterSecureStorage();

  AdminUser? user;
  String? notice; // pesan di halaman login (mis. "Sesi berakhir")
  bool ready = false;

  bool get loggedIn => user != null;

  Future<String?> _read() async {
    try {
      return await _store.read(key: _key);
    } catch (_) {
      return null; // web/private mode: simpan di memori saja
    }
  }

  Future<void> _write(String? v) async {
    try {
      if (v == null) {
        await _store.delete(key: _key);
      } else {
        await _store.write(key: _key, value: v);
      }
    } catch (_) {}
  }

  /// Dipanggil saat app dibuka: pulihkan token lalu validasi ke /api/admin/me.
  Future<void> restore() async {
    Api.instance.onUnauthorized = () => logout(notice: 'Sesi berakhir. Silakan login lagi.');
    final saved = await _read();
    if (saved != null) {
      Api.instance.token = saved;
      try {
        user = _parse(await Api.instance.get('/api/admin/me').timeout(const Duration(seconds: 8)));
      } catch (_) {
        Api.instance.token = null;
        await _write(null);
      }
    }
    ready = true;
    notifyListeners();
  }

  AdminUser _parse(dynamic m) {
    final map = m as Map;
    if (map['role'] != 'admin') throw ApiException(403, 'Akun ini bukan admin.');
    return AdminUser(id: (map['id'] as num).toInt(), name: '${map['name']}', email: '${map['email']}');
  }

  Future<void> login(String email, String password) async {
    final res = await Api.instance.login(email, password) as Map;
    final token = res['token'] as String;
    Api.instance.token = token;
    try {
      user = _parse(await Api.instance.get('/api/admin/me'));
    } on ApiException catch (e) {
      Api.instance.token = null;
      throw ApiException(e.status, e.status == 403 ? 'Akun ini bukan admin.' : e.message);
    }
    await _write(token);
    notice = null;
    notifyListeners();
  }

  Future<void> logout({String? notice}) async {
    Api.instance.token = null;
    user = null;
    this.notice = notice;
    await _write(null);
    notifyListeners();
  }
}
