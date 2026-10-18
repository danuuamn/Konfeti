import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/api_client.dart';
import '../core/session.dart';
import '../models/event.dart';
import 'local_db.dart';
import 'time_zones.dart';

/// Notifikasi mobile tanpa Firebase:
///  1. Polling GET /api/notifications (promo, status pembayaran, darurat) -> tampil sebagai notifikasi lokal.
///  2. Pengingat konser (H-1 dan 3 jam sebelumnya) dijadwalkan di perangkat dari daftar tiket aktif.
/// Notifikasi hanya muncul selama aplikasi masih hidup (foreground/background), karena tidak ada push server.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Kunci pengaturan (tabel app_settings) untuk saklar notifikasi di halaman Settings.
  static const String settingEnabled = 'notifications_enabled';
  static const String _settingLastId = 'last_notif_id';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'konfeti_main',
      'Konfeti notifications',
      channelDescription: 'Promos, payment status and event reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Jumlah notifikasi yang belum dibaca (untuk badge di tab Profile).
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  bool _ready = false;
  bool _observing = false;
  bool _polling = false;
  Timer? _timer;

  bool get running => _timer != null;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Dipanggil saat user login (aman dipanggil berulang).
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => poll());
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await _init();
    await poll();
    await syncReminders();
  }

  /// Dipanggil saat logout: hentikan polling dan batalkan pengingat milik akun tadi.
  void stop() {
    _timer?.cancel();
    _timer = null;
    unread.value = 0;
    if (_ready) {
      unawaited(_plugin.cancelAll().catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && running) unawaited(poll());
  }

  /// Ambil notifikasi dari server, perbarui badge, dan tampilkan yang baru sebagai notifikasi lokal.
  Future<void> poll() async {
    if (_polling || !Session.instance.loggedIn) return;
    _polling = true;
    try {
      final raw = await ApiClient.instance.get('/api/notifications') as List;
      final items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      bool isUnread(Map<String, dynamic> n) => ((n['is_read'] as num?)?.toInt() ?? 0) == 0;
      int idOf(Map<String, dynamic> n) => (n['id'] as num).toInt();

      unread.value = items.where(isUnread).length;
      if (items.isEmpty) return;

      final uid = currentUserId();
      final last = await LocalDb.instance.getInt(uid, _settingLastId) ?? 0;
      final maxId = items.map(idOf).reduce((a, b) => a > b ? a : b);
      final fresh = items.where((n) => isUnread(n) && idOf(n) > last).toList()
        ..sort((a, b) => idOf(a).compareTo(idOf(b)));
      if (maxId > last) await LocalDb.instance.setInt(uid, _settingLastId, maxId);
      if (fresh.isEmpty) return;

      final enabled = await LocalDb.instance.getBool(uid, settingEnabled, defaultValue: true);
      if (!enabled || !_ready) return;

      // maksimal 3 notifikasi terbaru per putaran supaya tidak membanjiri layar
      final toShow = fresh.length > 3 ? fresh.sublist(fresh.length - 3) : fresh;
      for (final n in toShow) {
        await _plugin.show(
          id: idOf(n),
          title: (n['title'] ?? 'Konfeti').toString(),
          body: (n['body'] ?? '').toString(),
          notificationDetails: _details,
        );
      }
      // pembayaran baru biasanya berarti ada tiket baru -> jadwalkan pengingatnya
      unawaited(syncReminders());
    } catch (_) {
      // server belum jalan / jaringan putus: coba lagi di putaran berikutnya
    } finally {
      _polling = false;
    }
  }

  static int _reminderId(int eventId, int slot) => 1000000 + eventId * 10 + slot;

  /// Jadwalkan ulang pengingat H-1 dan 3 jam sebelum event untuk setiap tiket aktif.
  Future<void> syncReminders() async {
    if (!_ready || !Session.instance.loggedIn) return;
    try {
      final enabled = await LocalDb.instance.getBool(currentUserId(), settingEnabled, defaultValue: true);
      final raw = await ApiClient.instance.get('/api/tickets') as List;
      final byEvent = <int, Ticket>{};
      for (final e in raw) {
        final t = Ticket.fromJson(Map<String, dynamic>.from(e as Map));
        if (t.state == 'active') byEvent.putIfAbsent(t.eventId, () => t);
      }
      for (final t in byEvent.values) {
        await _plugin.cancel(id: _reminderId(t.eventId, 1));
        await _plugin.cancel(id: _reminderId(t.eventId, 2));
        if (!enabled) continue;
        final p = zoneParts(t.startUtc, 'Asia/Jakarta');
        final when = '${p.time} ${p.abbr}';
        await _schedule(
          t,
          const Duration(hours: 24),
          1,
          'Tomorrow: ${t.title}',
          'Starts at $when at ${t.venueName}. Don\'t forget your e-ticket!',
        );
        await _schedule(
          t,
          const Duration(hours: 3),
          2,
          'Starting soon: ${t.title}',
          'The show starts at $when at ${t.venueName}. Have your e-ticket ready.',
        );
      }
    } catch (e) {
      debugPrint('Reminder sync failed: $e');
    }
  }

  Future<void> _schedule(Ticket t, Duration before, int slot, String title, String body) async {
    final fireAt = t.startUtc.subtract(before);
    if (!fireAt.isAfter(DateTime.now().toUtc())) return; // waktunya sudah lewat
    await _plugin.zonedSchedule(
      id: _reminderId(t.eventId, slot),
      title: title,
      body: body,
      // hanya instan waktunya yang penting, zona apa pun menghasilkan jadwal yang sama
      scheduledDate: tz.TZDateTime.from(fireAt, tz.getLocation('Asia/Jakarta')),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Notifikasi uji (tombol di Settings), berguna untuk demo.
  Future<void> showNow(String title, String body) async {
    await _init();
    if (!_ready) return;
    await _plugin.show(id: 999999, title: title, body: body, notificationDetails: _details);
  }
}
