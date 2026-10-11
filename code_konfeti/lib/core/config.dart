/// Konfigurasi aplikasi. Ganti lewat --dart-define saat run, contoh:
///   flutter run --dart-define=API_URL=http://192.168.1.10:3000
class AppConfig {
  /// 10.0.2.2 = localhost laptop jika dijalankan di Android Emulator.
  /// HP fisik: pakai IP LAN laptop atau URL ngrok.
  static const String apiBase =
      String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

  /// true = detail tiket bisa dibuka kapan saja (untuk demo/presentasi, karena
  /// event seed baru mulai beberapa hari lagi). Set false untuk perilaku asli.
  static const bool demoUnlockTickets =
      bool.fromEnvironment('DEMO_UNLOCK', defaultValue: true);

  /// Detail tiket bisa dibuka mulai sekian lama sebelum event dimulai.
  static const Duration earlyAccess = Duration(hours: 2);

  static const int maxQtyPerOrder = 5; // sama dengan batas di backend
}
