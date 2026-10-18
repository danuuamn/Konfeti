/// Waktu dari SQLite server berbentuk "2026-10-17 14:05:09" (UTC, tanpa penanda zona).
/// Mengembalikan waktu lokal perangkat, atau null jika formatnya tidak dikenali.
DateTime? parseServerTime(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(iso);
  return DateTime.tryParse(hasZone ? iso : '${iso}Z')?.toLocal();
}
