import 'dart:math';

/// ISO-8601 UTC dengan milidetik, sama bentuknya dengan Date.toISOString() di JavaScript.
String isoMs(DateTime d) {
  final u = d.toUtc();
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return '${p(u.year, 4)}-${p(u.month, 2)}-${p(u.day, 2)}T'
      '${p(u.hour, 2)}:${p(u.minute, 2)}:${p(u.second, 2)}.${p(u.millisecond, 3)}Z';
}

/// Mirip Number(x) di JavaScript, tapi null bila bukan angka hingga (NaN/Infinity juga null).
double? numOf(Object? v) {
  double? out;
  if (v is num) {
    out = v.toDouble();
  } else if (v is String) {
    final t = v.trim();
    if (t.isNotEmpty) out = double.tryParse(t);
  } else if (v is bool) {
    out = v ? 1.0 : 0.0;
  }
  if (out == null || out.isNaN || out.isInfinite) return null;
  return out;
}

bool isWhole(double d) => d == d.truncateToDouble();

/// Mirip String(x) di JavaScript untuk angka bulat (75000.0 menjadi "75000").
String jsString(Object? v) {
  if (v == null) return 'undefined';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Truthy ala JavaScript.
bool truthy(Object? v) => !(v == null || v == false || v == 0 || v == '');

/// 1500000 -> "1,500,000" (sama dengan toLocaleString('en-US')).
String formatThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

List<T> shuffled<T>(List<T> items) {
  final copy = List<T>.of(items);
  copy.shuffle(Random());
  return copy;
}

/// Kode heksadesimal acak yang aman secara kriptografi (huruf besar).
String randomHex(int bytes) {
  final r = Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString().toUpperCase();
}

/// 'YYYY-MM-DD HH:MM:SS' (UTC): format kolom created_at di database (SQLite maupun Postgres).
String sqlTs(DateTime d) {
  final u = d.toUtc();
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return '${p(u.year, 4)}-${p(u.month, 2)}-${p(u.day, 2)} ${p(u.hour, 2)}:${p(u.minute, 2)}:${p(u.second, 2)}';
}
