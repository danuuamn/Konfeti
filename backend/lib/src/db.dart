import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:sqlite3/sqlite3.dart' as sq;

import 'env.dart';
import 'schema.dart';

class RunResult {
  const RunResult(this.changes);

  /// Jumlah baris yang terpengaruh (INSERT/UPDATE/DELETE).
  final int changes;
}

/// Akses database yang sama untuk dua mesin:
///  - SQLite  : file lokal `app.db` (default, tanpa konfigurasi)
///  - Postgres: Supabase, aktif bila `DATABASE_URL` diisi di `.env`
///
/// Semua metode async. Tulis SQL dengan placeholder `?`; untuk Postgres otomatis diubah menjadi $1, $2, ...
/// Gunakan SQL yang lolos di kedua mesin (tanpa fungsi khusus SQLite seperti datetime('now') atau MAX(a,b)).
abstract class AppDb {
  /// 'sqlite' atau 'postgres'.
  String get kind;

  static Future<AppDb> open() async {
    final url = Env.get('DATABASE_URL');
    if (url.isNotEmpty) return PgDb.open(url);
    return SqliteDb.open();
  }

  /// Database khusus akun/login (tabel `users`): SELALU SQLite lokal, tidak pernah Supabase.
  /// Bila database utama sudah SQLite, objek yang sama dipakai ulang.
  static AppDb usersFor(AppDb main) => main is SqliteDb ? main : SqliteDb.openUsersOnly();

  /// SELECT banyak baris -> list of map.
  Future<List<Map<String, Object?>>> all(String sql, [List<Object?> params = const <Object?>[]]);

  /// SELECT satu baris (atau null).
  Future<Map<String, Object?>?> one(String sql, [List<Object?> params = const <Object?>[]]) async {
    final rows = await all(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  /// INSERT / UPDATE / DELETE.
  Future<RunResult> run(String sql, [List<Object?> params = const <Object?>[]]);

  /// INSERT ke tabel ber-id otomatis; mengembalikan id baris baru.
  Future<int> insert(String sql, [List<Object?> params = const <Object?>[]]);

  /// Jalankan [fn] dalam satu transaksi (ROLLBACK bila terjadi error).
  /// Di dalam [fn] WAJIB memakai `tx` (bukan db luar).
  Future<T> transaction<T>(Future<T> Function(AppDb tx) fn);

  Future<void> close();
}

// ---------------------------------------------------------------- SQLite

class SqliteDb extends AppDb {
  SqliteDb._(this._raw);

  final sq.Database _raw;
  Future<void> _txQueue = Future<void>.value();

  @override
  String get kind => 'sqlite';

  static SqliteDb open() {
    final path = Env.get('DB_PATH', '${Directory.current.path}${Platform.pathSeparator}app.db');
    final raw = sq.sqlite3.open(path);
    raw.execute('PRAGMA journal_mode = WAL;');
    raw.execute('PRAGMA foreign_keys = ON;');
    for (final statement in schemaStatements) {
      raw.execute(statement);
    }
    // Migrasi untuk app.db lama (dibuat sebelum ada kategori tiket / fitur admin)
    void addColumn(String table, String column, String definition) {
      final existing = raw.select('PRAGMA table_info($table)').map((row) => row['name']).toSet();
      if (!existing.contains(column)) raw.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }

    addColumn('transactions', 'tier_id', 'INTEGER');
    addColumn('transactions', 'tier_name', 'TEXT');
    addColumn('transactions', 'holder_name', 'TEXT');
    addColumn('transactions', 'holder_nik', 'TEXT');
    addColumn('transactions', 'holder_age', 'INTEGER');
    addColumn('transactions', 'holder_gender', 'TEXT');
    addColumn('users', 'role', "TEXT NOT NULL DEFAULT 'user'");
    addColumn('events', 'status', "TEXT NOT NULL DEFAULT 'active'");
    addColumn('tickets', 'used_at', 'TEXT');
    addColumn('tickets', 'checked_in_by', 'INTEGER REFERENCES users(id)');
    addColumn('emergency_alerts', 'responded_at', 'TEXT');
    addColumn('emergency_alerts', 'responded_by', 'INTEGER REFERENCES users(id)');
    return SqliteDb._(raw);
  }

  /// SQLite yang hanya berisi tabel `users` (file yang sama dengan app.db / DB_PATH).
  /// Dipakai saat data lain ada di Supabase tetapi login harus tetap lokal.
  static SqliteDb openUsersOnly() {
    final path = Env.get('DB_PATH', '${Directory.current.path}${Platform.pathSeparator}app.db');
    final raw = sq.sqlite3.open(path);
    raw.execute('PRAGMA journal_mode = WAL;');
    raw.execute(schemaStatements.first); // CREATE TABLE IF NOT EXISTS users
    final cols = raw.select('PRAGMA table_info(users)').map((row) => row['name']).toSet();
    if (!cols.contains('role')) raw.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'");
    return SqliteDb._(raw);
  }

  @override
  Future<List<Map<String, Object?>>> all(String sql, [List<Object?> params = const <Object?>[]]) async {
    final result = _raw.select(sql, params);
    final out = <Map<String, Object?>>[];
    for (final row in result) {
      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  @override
  Future<RunResult> run(String sql, [List<Object?> params = const <Object?>[]]) async {
    _raw.execute(sql, params);
    return RunResult(_raw.updatedRows);
  }

  @override
  Future<int> insert(String sql, [List<Object?> params = const <Object?>[]]) async {
    _raw.execute(sql, params);
    return _raw.lastInsertRowId;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDb tx) fn) {
    // Antrikan transaksi supaya dua transaksi tidak pernah saling menumpuk di satu koneksi.
    final previous = _txQueue;
    final done = Completer<void>();
    _txQueue = done.future;
    return previous.then((_) async {
      _raw.execute('BEGIN');
      try {
        final result = await fn(this);
        _raw.execute('COMMIT');
        return result;
      } catch (e) {
        try {
          _raw.execute('ROLLBACK');
        } catch (_) {}
        rethrow;
      } finally {
        done.complete();
      }
    });
  }

  @override
  Future<void> close() async => _raw.dispose();
}

// ---------------------------------------------------------------- Postgres (Supabase)

class PgDb extends AppDb {
  PgDb._(this._session, this._pool);

  final pg.Session _session;
  final pg.Pool<void>? _pool; // null untuk objek transaksi

  @override
  String get kind => 'postgres';

  /// [url] berbentuk postgresql://USER:PASSWORD@HOST:PORT/DATABASE
  /// (karakter khusus di password harus di-URL-encode, mis. @ menjadi %40).
  static Future<PgDb> open(String url) async {
    final u = Uri.parse(url);
    final info = u.userInfo;
    final colon = info.indexOf(':');
    final user = Uri.decodeComponent(colon < 0 ? info : info.substring(0, colon));
    final password = colon < 0 ? '' : Uri.decodeComponent(info.substring(colon + 1));
    final dbName = u.path.length > 1 ? u.path.substring(1) : 'postgres';
    final endpoint = pg.Endpoint(
      host: u.host,
      port: u.hasPort ? u.port : 5432,
      database: dbName,
      username: user,
      password: password,
    );
    final pool = pg.Pool<void>.withEndpoints(
      <pg.Endpoint>[endpoint],
      settings: const pg.PoolSettings(maxConnectionCount: 4, sslMode: pg.SslMode.require),
    );
    final db = PgDb._(pool, pool);
    for (final statement in pgSchemaStatements) {
      await db._session.execute(statement);
    }
    // Migrasi untuk tabel lama di Supabase (CREATE TABLE IF NOT EXISTS tidak menambah kolom)
    for (final col in const <String>[
      'holder_name TEXT',
      'holder_nik TEXT',
      'holder_age INTEGER',
      'holder_gender TEXT',
    ]) {
      await db._session.execute('ALTER TABLE transactions ADD COLUMN IF NOT EXISTS $col');
    }
    await db._session.execute('ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS responded_at TEXT');
    await db._session.execute('ALTER TABLE emergency_alerts ADD COLUMN IF NOT EXISTS responded_by BIGINT');
    // Data login ada di SQLite, jadi foreign key ke users di Supabase dilepas (kalau masih ada dari versi lama).
    await db._session.execute(r'''
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT conrelid::regclass AS tbl, conname FROM pg_constraint
           WHERE contype = 'f' AND confrelid = to_regclass('public.users')
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
  END LOOP;
END $$''');
    return db;
  }

  /// `?` -> $1, $2, ... (di luar tanda kutip) dan LIKE -> ILIKE (di SQLite LIKE tidak peka huruf besar/kecil).
  static String translate(String sql) {
    final out = StringBuffer();
    var n = 0;
    var inQuote = false;
    for (var i = 0; i < sql.length; i++) {
      final ch = sql[i];
      if (ch == "'") {
        inQuote = !inQuote;
        out.write(ch);
      } else if (!inQuote && ch == '?') {
        n++;
        out.write('\$$n');
      } else {
        out.write(ch);
      }
    }
    return out.toString().replaceAllMapped(RegExp(r'\bLIKE\b'), (_) => 'ILIKE');
  }

  Future<pg.Result> _exec(String sql, List<Object?> params) {
    return _session.execute(translate(sql), parameters: params.isEmpty ? null : params);
  }

  @override
  Future<List<Map<String, Object?>>> all(String sql, [List<Object?> params = const <Object?>[]]) async {
    final result = await _exec(sql, params);
    return result.map((row) => Map<String, Object?>.from(row.toColumnMap())).toList();
  }

  @override
  Future<RunResult> run(String sql, [List<Object?> params = const <Object?>[]]) async {
    final result = await _exec(sql, params);
    return RunResult(result.affectedRows);
  }

  @override
  Future<int> insert(String sql, [List<Object?> params = const <Object?>[]]) async {
    final result = await _exec('$sql RETURNING id', params);
    final v = result.first.toColumnMap()['id'];
    return v is int ? v : (v as num).toInt();
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDb tx) fn) {
    final pool = _pool;
    if (pool == null) return fn(this); // sudah di dalam transaksi
    return pool.runTx<T>((session) => fn(PgDb._(session, null)));
  }

  @override
  Future<void> close() async {
    await _pool?.close();
  }
}
