import 'dart:io';

/// Membaca konfigurasi dari environment OS dan file `.env` (di folder tempat server dijalankan).
/// Environment OS selalu menang atas isi `.env`, sama seperti paket dotenv di Node.js.
class Env {
  static final Map<String, String> _file = <String, String>{};

  static void load([String path = '.env']) {
    final f = File(path);
    if (!f.existsSync()) return;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (i == 0 && line.startsWith('\uFEFF')) line = line.substring(1); // buang BOM Windows
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      final quoted = value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")));
      if (quoted) {
        value = value.substring(1, value.length - 1);
      } else {
        final hash = value.indexOf(' #');
        if (hash >= 0) value = value.substring(0, hash).trim();
      }
      _file[key] = value;
    }
  }

  static String get(String key, [String fallback = '']) {
    final v = Platform.environment[key] ?? _file[key];
    if (v == null || v.isEmpty) return fallback;
    return v;
  }

  /// True bila variabel ada dan tidak kosong.
  static bool has(String key) => get(key).isNotEmpty;

  static bool get devRoutes => get('ALLOW_DEV_ROUTES') == 'true';
}
