import 'dart:io';

import 'package:konfeti_backend/src/db.dart';
import 'package:konfeti_backend/src/env.dart';

/// Menyalin isi SQLite lokal (app.db) ke Supabase/Postgres (DATABASE_URL di .env).
/// Aman dijalankan ulang: baris yang sudah ada dilewati (ON CONFLICT DO NOTHING).
///
///   dart run bin/migrate_to_supabase.dart
Future<void> main() async {
  Env.load();
  final url = Env.get('DATABASE_URL');
  if (url.isEmpty) {
    stderr.writeln('DATABASE_URL di .env masih kosong. Isi dulu dengan connection string Supabase.');
    exit(64);
  }

  final src = SqliteDb.open();
  final dst = await PgDb.open(url);

  // Urutan penting karena foreign key.
  const tables = <String, String?>{
    'users': 'id',
    'events': 'id',
    'ticket_tiers': 'id',
    'transactions': null,
    'tickets': 'id',
    'blocks': null,
    'notifications': 'id',
    'promos': null,
    'course_feedback': 'id',
    'emergency_alerts': 'id',
    'admin_logs': 'id',
  };

  try {
    for (final entry in tables.entries) {
      final table = entry.key;
      final rows = await src.all('SELECT * FROM $table');
      if (rows.isEmpty) {
        print('$table: kosong, dilewati');
        continue;
      }
      final cols = rows.first.keys.toList();
      final sql = 'INSERT INTO $table(${cols.join(',')}) VALUES(${List<String>.filled(cols.length, '?').join(',')}) '
          'ON CONFLICT DO NOTHING';
      var copied = 0;
      await dst.transaction<void>((tx) async {
        for (final r in rows) {
          final res = await tx.run(sql, cols.map((c) => r[c]).toList());
          copied += res.changes;
        }
      });
      print('$table: ${rows.length} baris di SQLite, $copied baris baru disalin');

      final idCol = entry.value;
      if (idCol != null) {
        // Samakan counter auto-id Postgres dengan data yang baru masuk.
        await dst.run(
          "SELECT setval(pg_get_serial_sequence('$table','$idCol'), "
          'COALESCE((SELECT MAX($idCol) FROM $table), 1), (SELECT MAX($idCol) FROM $table) IS NOT NULL)',
        );
      }
    }
    print('Selesai. Jalankan server seperti biasa (dart run bin/server.dart).');
  } finally {
    await src.close();
    await dst.close();
  }
}
