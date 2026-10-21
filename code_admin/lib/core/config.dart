import 'package:flutter/foundation.dart' show kIsWeb;

/// Ganti lewat --dart-define, contoh: flutter run --dart-define=API_URL=http://192.168.1.10:3000
class AppConfig {
  static const String _api = String.fromEnvironment('API_URL');

  /// Emulator Android: 10.0.2.2 = localhost laptop. Web: localhost.
  static String get apiBase => _api.isNotEmpty ? _api : (kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000');

  /// Tidak ada aktivitas selama ini -> logout otomatis.
  static const Duration sessionTimeout = Duration(minutes: 15);

  /// Peringatan muncul sekian lama sebelum logout.
  static const Duration sessionWarning = Duration(seconds: 30);

  static const int pageSize = 20;
}
