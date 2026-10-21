import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_db.dart';

/// Data diri terakhir yang dipakai saat checkout (nama, NIK, umur, gender).
/// Disimpan di penyimpanan terenkripsi (bukan SQLite biasa) karena berisi NIK, dan terpisah per akun.
class CheckoutDraft {
  const CheckoutDraft({required this.name, required this.nik, required this.age, required this.gender});

  final String name;
  final String nik;
  final String age;
  final String gender; // 'Male' | 'Female'

  /// NIK disamarkan untuk ditampilkan: 3404••••••••1234
  String get maskedNik => nik.length < 8 ? nik : '${nik.substring(0, 4)}••••••••${nik.substring(nik.length - 4)}';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String get _key => 'checkout_draft_${currentUserId()}';

  /// Null bila belum ada data tersimpan (atau rusak).
  static Future<CheckoutDraft?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map;
      final d = CheckoutDraft(
        name: (j['name'] ?? '').toString(),
        nik: (j['nik'] ?? '').toString(),
        age: (j['age'] ?? '').toString(),
        gender: (j['gender'] ?? '').toString(),
      );
      return (d.name.isEmpty || d.nik.isEmpty) ? null : d;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required String name,
    required String nik,
    required String age,
    required String gender,
  }) async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode(<String, String>{'name': name, 'nik': nik, 'age': age, 'gender': gender}),
      );
    } catch (_) {
      // gagal menyimpan draf tidak boleh menggagalkan pembayaran
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
