import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'env.dart';
import 'schema.dart';

class RunResult {
  const RunResult(this.lastInsertId, this.changes);
  final int lastInsertId;
  final int changes;
}

/// Pembungkus tipis di atas paket sqlite3 supaya route tetap ringkas.
class AppDb {
  AppDb._(this._raw);

  final Database _raw;

  static AppDb open() {
    final path = Env.get('DB_PATH', '${Directory.current.path}${Platform.pathSeparator}app.db');
    final raw = sqlite3.open(path);
    raw.execute('PRAGMA journal_mode = WAL;');
    raw.execute('PRAGMA foreign_keys = ON;');
    for (final statement in schemaStatements) {
      raw.execute(statement);
    }
    return AppDb._(raw);
  }

  /// SELECT banyak baris -> list of map.
  List<Map<String, Object?>> all(String sql, [List<Object?> params = const <Object?>[]]) {
    final result = _raw.select(sql, params);
    final out = <Map<String, Object?>>[];
    for (final row in result) {
      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  /// SELECT satu baris (atau null).
  Map<String, Object?>? one(String sql, [List<Object?> params = const <Object?>[]]) {
    final rows = all(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  /// INSERT / UPDATE / DELETE.
  RunResult run(String sql, [List<Object?> params = const <Object?>[]]) {
    _raw.execute(sql, params);
    return RunResult(_raw.lastInsertRowId, _raw.updatedRows);
  }

  /// Jalankan [fn] di dalam BEGIN/COMMIT (ROLLBACK bila terjadi error).
  T transaction<T>(T Function() fn) {
    _raw.execute('BEGIN');
    try {
      final result = fn();
      _raw.execute('COMMIT');
      return result;
    } catch (e) {
      try {
        _raw.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }
}
