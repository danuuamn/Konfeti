import '../db.dart';

/// Tabel `users` (data login) selalu di SQLite lokal, sedangkan event/order/tiket bisa di Supabase.
/// Dua database berbeda tidak bisa di-JOIN, jadi nama/email user ditempelkan lewat fungsi di bawah.

/// Menempelkan kolom user ke tiap baris.
/// [spec] = { kolom id di baris : { nama kunci hasil : kolom di tabel users } }, mis.
/// `{'user_id': {'user_name': 'name', 'user_email': 'email'}}`.
/// Kolom yang boleh dipakai: name, email, role, avatar_url (nilai berasal dari kode, bukan dari user).
Future<void> attachUsers(AppDb udb, List<Map<String, Object?>> rows, Map<String, Map<String, String>> spec) async {
  if (rows.isEmpty) return;
  const allowed = <String>{'name', 'email', 'role', 'avatar_url'};
  final ids = <int>{};
  for (final idKey in spec.keys) {
    for (final r in rows) {
      final v = r[idKey];
      if (v is num) ids.add(v.toInt());
    }
  }
  final byId = <int, Map<String, Object?>>{};
  final list = ids.toList();
  for (var i = 0; i < list.length; i += 500) {
    final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
    final found = await udb.all(
      'SELECT id, name, email, role, avatar_url FROM users WHERE id IN (${List<String>.filled(chunk.length, '?').join(',')})',
      chunk,
    );
    for (final u in found) {
      byId[(u['id'] as num).toInt()] = u;
    }
  }
  for (final r in rows) {
    spec.forEach((idKey, outs) {
      final v = r[idKey];
      final u = v is num ? byId[v.toInt()] : null;
      outs.forEach((outKey, col) {
        assert(allowed.contains(col));
        r[outKey] = u?[col];
      });
    });
  }
}

/// Id user yang namanya atau emailnya cocok dengan [q] (untuk pencarian di tabel yang ada di Supabase).
Future<List<int>> searchUserIds(AppDb udb, String q, {int limit = 500}) async {
  final rows = await udb.all(
    'SELECT id FROM users WHERE name LIKE ? OR email LIKE ? LIMIT ?',
    <Object?>['%$q%', '%$q%', limit],
  );
  return rows.map((r) => (r['id'] as num).toInt()).toList();
}

/// Kirim notifikasi ke semua user. Mengembalikan jumlah penerima.
Future<int> notifyAllUsers(AppDb db, AppDb udb, String title, String body) async {
  final ids = (await udb.all('SELECT id FROM users')).map((r) => (r['id'] as num).toInt()).toList();
  if (ids.isEmpty) return 0;
  await db.transaction<void>((tx) async {
    for (final id in ids) {
      await tx.run('INSERT INTO notifications(user_id,title,body) VALUES(?,?,?)', <Object?>[id, title, body]);
    }
  });
  return ids.length;
}

/// Pindahkan akun lama dari tabel `users` di Supabase ke SQLite (id dipertahankan supaya order/tiket lama
/// tetap cocok). Hanya berjalan bila SQLite masih kosong. Mengembalikan pesan untuk dicetak, atau null.
Future<String?> migrateUsersFromPostgres(AppDb main, AppDb udb) async {
  if (main.kind != 'postgres') return null;
  final t = await main.one(
    "SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema='public' AND table_name='users'",
  );
  if (t == null || (t['n'] as num).toInt() == 0) return null;
  final have = (await udb.one('SELECT COUNT(*) AS n FROM users'))!['n'] as num;
  if (have.toInt() > 0) {
    return 'PERHATIAN: tabel users masih ada di Supabase. Login sudah memakai SQLite, jadi tabel itu boleh dihapus: DROP TABLE users;';
  }
  final rows = await main.all('SELECT id, name, email, password_hash, avatar_url, role, created_at FROM users ORDER BY id');
  for (final u in rows) {
    await udb.run(
      'INSERT INTO users(id,name,email,password_hash,avatar_url,role,created_at) VALUES(?,?,?,?,?,?,?)',
      <Object?>[u['id'], u['name'], u['email'], u['password_hash'], u['avatar_url'], u['role'] ?? 'user', u['created_at']],
    );
  }
  return '${rows.length} akun disalin dari Supabase ke SQLite. Setelah dicek, hapus tabel lama di Supabase (SQL Editor): DROP TABLE users;';
}
