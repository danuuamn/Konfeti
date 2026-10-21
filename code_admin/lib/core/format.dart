import 'package:intl/intl.dart';

final NumberFormat _idr = NumberFormat.decimalPattern('id_ID');
final DateFormat _dt = DateFormat('dd MMM yyyy, HH:mm');
final DateFormat _d = DateFormat('dd MMM');

String rp(Object? v) => 'Rp ${_idr.format(num.tryParse('${v ?? 0}') ?? 0)}';
String num0(Object? v) => _idr.format(num.tryParse('${v ?? 0}') ?? 0);

/// Server mengirim ISO ("...Z") atau "YYYY-MM-DD HH:MM:SS" (UTC tanpa zona). Keduanya dibaca sebagai UTC.
DateTime? parseUtc(Object? v) {
  if (v is! String || v.isEmpty) return null;
  var s = v.trim().replaceFirst(' ', 'T');
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  if (!hasZone) s = '${s}Z';
  return DateTime.tryParse(s)?.toLocal();
}

String fmtDateTime(Object? v) {
  final d = parseUtc(v);
  return d == null ? '-' : _dt.format(d);
}

String fmtDay(Object? v) {
  // "YYYY-MM-DD" dari sales_by_day
  final d = DateTime.tryParse('$v');
  return d == null ? '$v' : _d.format(d);
}

int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
