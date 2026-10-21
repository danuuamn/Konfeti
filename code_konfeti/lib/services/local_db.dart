import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/session.dart';

/// Id user yang sedang login (0 jika belum ada). Dipakai supaya data lokal tidak tercampur antar akun.
int currentUserId() => (Session.instance.user?['id'] as num?)?.toInt() ?? 0;

/// Satu pesan di chat AI. role: 'user' atau 'model' (istilah Gemini).
class ChatMessage {
  const ChatMessage({required this.role, required this.text, this.id});
  final int? id;
  final String role;
  final String text;

  bool get isUser => role == 'user';
}

/// Database SQLite lokal (di perangkat): riwayat chat AI dan pengaturan per akun.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  /// Naik setiap kali riwayat chat dihapus; ChatPage mendengarkan ini untuk memuat ulang.
  final ValueNotifier<int> chatVersion = ValueNotifier<int>(0);

  Future<Database>? _opening;

  Future<Database> get _db async {
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null; // gagal membuka: coba lagi pada pemanggilan berikutnya
      rethrow;
    }
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'konfeti_local.db');
    return openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createOfflineTables(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  role TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE app_settings (
  user_id INTEGER NOT NULL,
  setting_key TEXT NOT NULL,
  setting_value TEXT NOT NULL,
  PRIMARY KEY (user_id, setting_key)
)''');
        await _createOfflineTables(db);
      },
    );
  }

  /// Tabel untuk mode offline: cache data server dan antrean SOS.
  Future<void> _createOfflineTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS cache_json (
  user_id INTEGER NOT NULL,
  cache_key TEXT NOT NULL,
  json TEXT NOT NULL,
  saved_at TEXT NOT NULL,
  PRIMARY KEY (user_id, cache_key)
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS sos_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  payload TEXT NOT NULL,
  occurred_at TEXT NOT NULL
)''');
  }

  // ---------- Cache data server (hanya untuk ditampilkan saat offline) ----------
  /// Simpan salinan JSON (mis. daftar tiket). Menimpa salinan lama dengan key yang sama.
  Future<void> putCache(int userId, String key, String json) async {
    final db = await _db;
    await db.insert(
      'cache_json',
      <String, Object?>{
        'user_id': userId,
        'cache_key': key,
        'json': json,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Ambil salinan JSON, atau null bila belum pernah disimpan.
  Future<String?> getCache(int userId, String key) async {
    final db = await _db;
    final rows = await db.query(
      'cache_json',
      columns: <String>['json'],
      where: 'user_id = ? AND cache_key = ?',
      whereArgs: <Object?>[userId, key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['json'] as String?;
  }

  /// Akun terakhir yang punya salinan tiket di HP (null = belum ada / sudah dihapus saat logout manual).
  Future<int?> lastTicketCacheUser() async {
    final db = await _db;
    final rows = await db.query(
      'cache_json',
      columns: <String>['user_id'],
      where: 'cache_key = ?',
      whereArgs: <Object?>['tickets'],
      orderBy: 'saved_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['user_id'] as int?;
  }

  /// Hapus semua cache milik satu akun (dipakai saat logout manual).
  Future<void> clearCache(int userId) async {
    final db = await _db;
    await db.delete('cache_json', where: 'user_id = ?', whereArgs: <Object?>[userId]);
  }

  // ---------- Antrean SOS offline ----------
  /// Simpan SOS yang gagal terkirim. [occurredAt] = waktu kejadian di HP (ISO UTC).
  Future<void> enqueueSos(int userId, String payloadJson, String occurredAt) async {
    final db = await _db;
    await db.insert('sos_outbox', <String, Object?>{
      'user_id': userId,
      'payload': payloadJson,
      'occurred_at': occurredAt,
    });
  }

  Future<List<Map<String, Object?>>> pendingSos(int userId) async {
    final db = await _db;
    return db.query('sos_outbox', where: 'user_id = ?', whereArgs: <Object?>[userId], orderBy: 'id ASC');
  }

  Future<void> deleteSos(int id) async {
    final db = await _db;
    await db.delete('sos_outbox', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // ---------- Riwayat chat ----------
  Future<List<ChatMessage>> chatHistory(int userId, {int limit = 200}) async {
    final db = await _db;
    final rows = await db.query(
      'chat_messages',
      where: 'user_id = ?',
      whereArgs: <Object?>[userId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed
        .map((r) => ChatMessage(id: r['id'] as int?, role: r['role'] as String, text: r['text'] as String))
        .toList();
  }

  Future<void> addChatMessage(int userId, String role, String text) async {
    final db = await _db;
    await db.insert('chat_messages', <String, Object?>{
      'user_id': userId,
      'role': role,
      'text': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> clearChat(int userId) async {
    final db = await _db;
    await db.delete('chat_messages', where: 'user_id = ?', whereArgs: <Object?>[userId]);
    chatVersion.value++;
  }

  // ---------- Pengaturan (key-value per akun) ----------
  Future<String?> getSetting(int userId, String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: <String>['setting_value'],
      where: 'user_id = ? AND setting_key = ?',
      whereArgs: <Object?>[userId, key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value'] as String?;
  }

  Future<void> setSetting(int userId, String key, String value) async {
    final db = await _db;
    await db.insert(
      'app_settings',
      <String, Object?>{'user_id': userId, 'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getBool(int userId, String key, {bool defaultValue = false}) async {
    final v = await getSetting(userId, key);
    return v == null ? defaultValue : v == '1';
  }

  Future<void> setBool(int userId, String key, bool value) => setSetting(userId, key, value ? '1' : '0');

  Future<int?> getInt(int userId, String key) async {
    final v = await getSetting(userId, key);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setInt(int userId, String key, int value) => setSetting(userId, key, value.toString());
}
