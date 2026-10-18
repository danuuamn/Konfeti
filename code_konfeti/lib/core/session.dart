import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/biometric_service.dart';
import 'api_client.dart';
import 'config.dart';

/// Sesi login: token JWT disimpan terenkripsi di flutter_secure_storage.
/// Juga mengurus login biometrik (opsional) dan batas waktu sesi (idle timeout).
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _key = 'jwt';
  static const _kBioEnabled = 'bio_enabled';
  static const _kBioToken = 'bio_token';
  static const _kBioMethod = 'bio_method'; // fingerprint | face
  static const _kLastActive = 'last_active'; // ISO 8601

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final BiometricService _bio = BiometricService();

  String? token;
  Map<String, dynamic>? user;
  bool get loggedIn => token != null;

  // --- biometrik ---
  bool bioAvailable = false; // perangkat punya sidik jari/wajah terdaftar
  bool bioEnabled = false; // pengguna mengaktifkan login biometrik
  bool hasBioToken = false; // ada token tersimpan untuk login cepat
  List<String> availableMethods = <String>[];
  String bioMethod = 'fingerprint';

  /// True bila pengguna baru saja dikeluarkan karena sesi berakhir (tidak aktif / token kedaluwarsa).
  bool sessionExpired = false;

  /// True sekali saja setelah app dibuka dan biometrik aktif: halaman login langsung memunculkan prompt.
  bool promptBiometric = false;

  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cek ulang ketersediaan biometrik (mis. setelah pengguna mendaftarkan sidik jari di pengaturan HP).
  Future<void> refreshBiometric() async {
    final avail = await _bio.isAvailable();
    final methods = await _bio.availableMethods();
    if (avail == bioAvailable && methods.join() == availableMethods.join()) return;
    bioAvailable = avail;
    availableMethods = methods;
    if (methods.isNotEmpty && !methods.contains(bioMethod)) bioMethod = methods.first;
    notifyListeners();
  }

  Future<void> restore() async {
    bioAvailable = await _bio.isAvailable();
    bioEnabled = (await _storage.read(key: _kBioEnabled)) == 'true';
    hasBioToken = bioEnabled && (await _storage.read(key: _kBioToken)) != null;
    availableMethods = await _bio.availableMethods();
    final savedMethod = await _storage.read(key: _kBioMethod);
    if (savedMethod != null && availableMethods.contains(savedMethod)) {
      bioMethod = savedMethod;
    } else if (availableMethods.isNotEmpty) {
      bioMethod = availableMethods.first;
    }

    final saved = await _storage.read(key: _key);
    if (saved == null) {
      notifyListeners();
      return;
    }

    // Sesi sudah lewat batas waktu selama app tertutup -> minta login lagi.
    final lastRaw = await _storage.read(key: _kLastActive);
    final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    if (last != null && DateTime.now().difference(last) >= AppConfig.sessionTimeout) {
      await _storage.delete(key: _key);
      sessionExpired = true;
      notifyListeners();
      return;
    }

    // Biometrik aktif -> buka kunci lewat halaman login (prompt otomatis), bukan langsung masuk.
    if (bioEnabled && bioAvailable && hasBioToken) {
      promptBiometric = true;
      notifyListeners();
      return;
    }

    token = saved;
    ApiClient.instance.token = token;
    try {
      user = Map<String, dynamic>.from(await ApiClient.instance.get('/api/auth/me') as Map);
      await saveActivity(DateTime.now(), force: true);
    } on ApiException catch (e) {
      if (e.status == 401) await logout(expired: true); // token basi; error jaringan -> tetap login
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
    if (bioEnabled) {
      await _storage.write(key: _kBioToken, value: token);
      hasBioToken = true;
    }
    await saveActivity(DateTime.now(), force: true);
    sessionExpired = false;
    notifyListeners();
  }

  /// Login cepat dari halaman login memakai token yang tersimpan (setelah logout / sesi berakhir / app dibuka).
  Future<void> loginWithBiometric() async {
    promptBiometric = false;
    final ok = await _bio.authenticate(_reason('sign in to Konfeti'));
    if (!ok) throw ApiException(0, 'Biometric authentication was cancelled.');
    final saved = await _storage.read(key: _kBioToken);
    if (saved == null) {
      throw ApiException(0, 'No saved biometric login. Sign in with your password first.');
    }
    ApiClient.instance.token = saved;
    try {
      user = Map<String, dynamic>.from(await ApiClient.instance.get('/api/auth/me') as Map);
    } on ApiException catch (e) {
      ApiClient.instance.token = null;
      if (e.status == 401) {
        // token biometrik sudah kedaluwarsa -> harus login dengan password sekali lagi
        await _storage.delete(key: _kBioToken);
        hasBioToken = false;
        notifyListeners();
      }
      rethrow;
    }
    token = saved;
    await _storage.write(key: _key, value: saved);
    await saveActivity(DateTime.now(), force: true);
    sessionExpired = false;
    notifyListeners();
  }

  /// Aktif/nonaktifkan login biometrik. Mengembalikan false bila gagal/dibatalkan.
  Future<bool> setBiometric(bool on) async {
    if (on) {
      if (!bioAvailable || token == null) return false;
      final ok = await _bio.authenticate(_reason('enable biometric login'));
      if (!ok) return false;
      await _storage.write(key: _kBioEnabled, value: 'true');
      await _storage.write(key: _kBioToken, value: token);
      bioEnabled = true;
      hasBioToken = true;
    } else {
      await _storage.delete(key: _kBioEnabled);
      await _storage.delete(key: _kBioToken);
      bioEnabled = false;
      hasBioToken = false;
    }
    notifyListeners();
    return true;
  }

  /// Pilih metode pilihan ('fingerprint' atau 'face').
  Future<void> setBioMethod(String method) async {
    if (!availableMethods.contains(method)) return;
    bioMethod = method;
    await _storage.write(key: _kBioMethod, value: method);
    notifyListeners();
  }

  String get bioLabel => bioMethod == 'face' ? 'face' : 'fingerprint';

  /// Android tidak bisa memaksa jenis biometrik; dialog sistem yang menentukan.
  /// Teks ini hanya mengarahkan pengguna ke metode pilihannya.
  String _reason(String action) {
    final how = bioMethod == 'face' ? 'Use your face to' : 'Touch the fingerprint sensor to';
    return '$how $action';
  }

  /// Simpan waktu aktivitas terakhir (dibatasi tiap 15 detik agar tidak boros).
  Future<void> saveActivity(DateTime at, {bool force = false}) async {
    if (!force && at.difference(_lastSaved) < const Duration(seconds: 15)) return;
    _lastSaved = at;
    await _storage.write(key: _kLastActive, value: at.toIso8601String());
  }

  void clearSessionExpired() {
    if (!sessionExpired) return;
    sessionExpired = false;
    notifyListeners();
  }

  /// Perbarui data user di memori (mis. setelah ganti nama / foto profil) dan beri tahu listener.
  void updateUser(Map<dynamic, dynamic> data) {
    user = Map<String, dynamic>.from(data);
    notifyListeners();
  }

  /// Keluar. [expired] true bila karena tidak aktif / token kedaluwarsa.
  /// Token biometrik tetap disimpan, jadi pengguna bisa masuk cepat lagi lewat sidik jari/wajah.
  Future<void> logout({bool expired = false}) async {
    token = null;
    user = null;
    ApiClient.instance.token = null;
    await _storage.delete(key: _key);
    await _storage.delete(key: _kLastActive);
    sessionExpired = expired;
    notifyListeners();
  }
}
