import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// Sesi login: token JWT disimpan terenkripsi di flutter_secure_storage.
/// Halaman login/register + biometrik milik Ilham tinggal memanggil login()/register().
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _key = 'jwt';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? token;
  Map<String, dynamic>? user;
  bool get loggedIn => token != null;

  Future<void> restore() async {
    token = await _storage.read(key: _key);
    ApiClient.instance.token = token;
    if (token != null) {
      try {
        user = Map<String, dynamic>.from(await ApiClient.instance.get('/api/auth/me') as Map);
      } on ApiException catch (e) {
        if (e.status == 401) await logout(); // token basi; error jaringan -> tetap login
      }
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = await ApiClient.instance
        .post('/api/auth/login', <String, Object?>{'email': email, 'password': password});
    await _accept(res as Map);
  }

  Future<void> register(String name, String email, String password) async {
    final res = await ApiClient.instance.post(
        '/api/auth/register', <String, Object?>{'name': name, 'email': email, 'password': password});
    await _accept(res as Map);
  }

  Future<void> _accept(Map res) async {
    token = res['token'] as String;
    user = Map<String, dynamic>.from(res['user'] as Map);
    ApiClient.instance.token = token;
    await _storage.write(key: _key, value: token);
    notifyListeners();
  }

  /// Perbarui data user di memori (mis. setelah ganti nama / foto profil) dan beri tahu listener.
  void updateUser(Map<dynamic, dynamic> data) {
    user = Map<String, dynamic>.from(data);
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;
    ApiClient.instance.token = null;
    await _storage.delete(key: _key);
    notifyListeners();
  }
}
