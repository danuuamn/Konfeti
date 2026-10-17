import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ZoneInfo {
  const ZoneInfo(this.label, this.tzName);
  final String label;
  final String tzName;
}

/// Zona waktu yang diminta dosen: WIB, WIT, WITA, London.
const List<ZoneInfo> eventZones = <ZoneInfo>[
  ZoneInfo('WIB', 'Asia/Jakarta'),
  ZoneInfo('WITA', 'Asia/Makassar'),
  ZoneInfo('WIT', 'Asia/Jayapura'),
  ZoneInfo('London', 'Europe/London'),
];

void initTimeZones() => tzdata.initializeTimeZones();

/// Mengubah waktu UTC dari server ke zona tertentu. London otomatis GMT/BST (musim panas).
({String text, String abbr}) convertToZone(DateTime utc, String tzName) {
  final t = tz.TZDateTime.from(utc.toUtc(), tz.getLocation(tzName));
  return (text: DateFormat('EEE, d MMM yyyy • HH:mm').format(t), abbr: t.timeZoneName);
}

/// Potongan tanggal/jam untuk tampilan kartu (hari, bulan, tanggal lengkap, jam).
({String day, String month, String date, String time, String abbr}) zoneParts(DateTime utc, String tzName) {
  final t = tz.TZDateTime.from(utc.toUtc(), tz.getLocation(tzName));
  return (
    day: DateFormat('d').format(t),
    month: DateFormat('MMM').format(t),
    date: DateFormat('d MMM yyyy').format(t),
    time: DateFormat('HH:mm').format(t),
    abbr: t.timeZoneName,
  );
}
