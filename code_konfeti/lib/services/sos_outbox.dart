import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/navigation.dart';
import 'local_db.dart';

/// Antrean SOS offline: alert yang gagal terkirim (tidak ada sinyal / server error) disimpan di SQLite
/// lokal, lalu dikirim ulang otomatis begitu koneksi kembali. Waktu kejadian ikut dikirim (`occurred_at`)
/// supaya staf tahu kapan alert sebenarnya ditekan, bukan kapan datanya sampai.
class SosOutbox {
  SosOutbox._();
  static final SosOutbox instance = SosOutbox._();

  Timer? _timer;
  bool _flushing = false;

  /// Mulai mencoba kirim ulang berkala. Dipanggil saat login; aman dipanggil berulang.
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => flush());
    flush();
  }

  /// Berhenti saat logout (antrean tetap tersimpan dan dilanjutkan saat akun itu login lagi).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Simpan alert ke antrean. [occurredAt] = saat user menekan/mengguncang.
  Future<void> enqueue(Map<String, Object?> payload, DateTime occurredAt) async {
    await LocalDb.instance.enqueueSos(currentUserId(), jsonEncode(payload), occurredAt.toUtc().toIso8601String());
    start();
  }

  /// Kirim semua alert milik akun yang sedang login. Mengembalikan jumlah yang berhasil terkirim.
  Future<int> flush() async {
    if (_flushing) return 0;
    final uid = currentUserId();
    if (uid == 0) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final rows = await LocalDb.instance.pendingSos(uid);
      for (final r in rows) {
        final payload = Map<String, Object?>.from(jsonDecode(r['payload'] as String) as Map);
        payload['occurred_at'] = r['occurred_at'];
        try {
          await ApiClient.instance.post('/api/emergency', payload);
          await LocalDb.instance.deleteSos(r['id'] as int);
          sent++;
        } on ApiException catch (e) {
          // Masih offline / server bermasalah / token habis: simpan, coba lagi nanti.
          if (e.status == 0 || e.status >= 500 || e.status == 401 || e.status == 429) break;
          // Ditolak server karena datanya tidak valid: buang supaya tidak mengulang selamanya.
          await LocalDb.instance.deleteSos(r['id'] as int);
        }
      }
    } catch (_) {
      // database lokal bermasalah: coba lagi pada putaran berikutnya
    } finally {
      _flushing = false;
    }
    if (sent > 0) {
      messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(sent == 1
            ? 'Your saved emergency alert has been sent to the staff.'
            : '$sent saved emergency alerts have been sent to the staff.'),
      ));
    }
    return sent;
  }
}
