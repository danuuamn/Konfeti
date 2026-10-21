import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import 'local_db.dart';
import 'notification_service.dart';

/// Notifikasi saat aplikasi DITUTUP, tanpa Firebase.
///
/// WorkManager (Android) menjalankan [konfetiBackgroundDispatcher] secara berkala (minimal tiap 15 menit,
/// waktu pastinya diatur sistem) walau aplikasi tidak dibuka. Tugasnya: baca token login dari secure storage,
/// panggil GET /api/notifications, lalu tampilkan notifikasi yang belum pernah ditampilkan.
/// "Sudah pernah ditampilkan" dicatat di SQLite lokal (kunci last_notif_id), sama dengan yang dipakai
/// NotificationService saat app terbuka, jadi tidak ada notifikasi ganda.
const String _taskName = 'konfeti_poll_notifications';
const String _uniqueName = 'konfeti_poll_notifications_periodic';
const String _kUid = 'bg_uid';
const String _kToken = 'jwt'; // sama dengan kunci di Session

const FlutterSecureStorage _storage = FlutterSecureStorage();

/// Titik masuk isolate latar belakang. Wajib top-level dan diberi entry-point agar tidak dihapus saat build release.
@pragma('vm:entry-point')
void konfetiBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await BackgroundNotifier.runOnce();
    } catch (e) {
      debugPrint('Background notification check failed: $e');
    }
    return true; // jangan di-retry cepat; putaran berkala berikutnya akan mencoba lagi
  });
}

class BackgroundNotifier {
  BackgroundNotifier._();

  static bool _initialized = false;

  /// Daftarkan tugas berkala (aman dipanggil berulang). Hanya Android.
  static Future<void> register(int userId) async {
    if (kIsWeb || !Platform.isAndroid || userId <= 0) return;
    try {
      await _storage.write(key: _kUid, value: '$userId');
      if (!_initialized) {
        await Workmanager().initialize(konfetiBackgroundDispatcher);
        _initialized = true;
      }
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('Background notifications not registered: $e');
    }
  }

  /// Hentikan tugas (saat logout).
  static Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
      await _storage.delete(key: _kUid);
    } catch (e) {
      debugPrint('Background notifications not cancelled: $e');
    }
  }

  /// Satu putaran pengecekan (dijalankan di isolate latar belakang).
  static Future<void> runOnce() async {
    final token = await _storage.read(key: _kToken);
    final uid = int.tryParse(await _storage.read(key: _kUid) ?? '');
    if (token == null || uid == null) return; // belum / sudah logout

    ApiClient.instance.token = token;
    final List<dynamic> raw;
    try {
      raw = await ApiClient.instance.get('/api/notifications') as List<dynamic>;
    } on ApiException catch (e) {
      if (e.status == 401) await cancel(); // token kedaluwarsa; app akan meminta login lagi saat dibuka
      return;
    }

    final items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (items.isEmpty) return;
    int idOf(Map<String, dynamic> n) => (n['id'] as num).toInt();
    bool isUnread(Map<String, dynamic> n) => ((n['is_read'] as num?)?.toInt() ?? 0) == 0;

    final last = await LocalDb.instance.getInt(uid, 'last_notif_id') ?? 0;
    final maxId = items.map(idOf).reduce((a, b) => a > b ? a : b);
    final fresh = items.where((n) => isUnread(n) && idOf(n) > last).toList()
      ..sort((a, b) => idOf(a).compareTo(idOf(b)));
    if (maxId > last) await LocalDb.instance.setInt(uid, 'last_notif_id', maxId);
    if (fresh.isEmpty) return;

    final enabled =
        await LocalDb.instance.getBool(uid, NotificationService.settingEnabled, defaultValue: true);
    if (!enabled) return;

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    final toShow = fresh.length > 3 ? fresh.sublist(fresh.length - 3) : fresh;
    for (final n in toShow) {
      await plugin.show(
        id: idOf(n), // id sama dengan di foreground -> menimpa, bukan dobel
        title: (n['title'] ?? 'Konfeti').toString(),
        body: (n['body'] ?? '').toString(),
        notificationDetails: NotificationService.details,
      );
    }
  }
}
