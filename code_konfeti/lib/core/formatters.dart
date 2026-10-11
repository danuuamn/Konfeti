import 'package:intl/intl.dart';

String _group(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}

/// 150000 -> "Rp 150.000"
String rupiah(int amount) => 'Rp ${_group(amount)}';

/// Format nominal dalam mata uang tertentu. IDR/JPY tanpa desimal, lainnya 2 desimal.
String money(double amount, String code) {
  if (code == 'IDR') return rupiah(amount.round());
  if (code == 'JPY') return '¥${NumberFormat('#,##0').format(amount.round())}';
  const symbols = <String, String>{'USD': r'$', 'EUR': '€', 'SGD': r'S$', 'MYR': 'RM '};
  return '${symbols[code] ?? '$code '}${NumberFormat('#,##0.00').format(amount)}';
}

String shortDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// Teks hitung mundur singkat, mis. "2d 4h" / "3h 20m" / "12m".
String countdown(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes.clamp(0, 59)}m';
}
