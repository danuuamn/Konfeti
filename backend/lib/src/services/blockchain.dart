import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db.dart';
import '../util.dart';

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

String _calc(int idx, String ts, String code, int uid, String prev) => _sha('$idx|$ts|$code|$uid|$prev');

/// Menambah satu block (tiket baru) ke rantai.
void addBlock(AppDb db, String ticketCode, int userId) {
  final last = db.one('SELECT * FROM blocks ORDER BY idx DESC LIMIT 1');
  final int idx = last == null ? 0 : (last['idx'] as int) + 1;
  final String prev = last == null ? '0' * 64 : last['hash'] as String;
  final ts = isoMs(DateTime.now());
  final hash = _calc(idx, ts, ticketCode, userId, prev);
  db.run('INSERT INTO blocks VALUES(?,?,?,?,?,?)', <Object?>[idx, ts, ticketCode, userId, prev, hash]);
}

class ChainResult {
  const ChainResult({required this.valid, this.brokenAt, this.length = 0});
  final bool valid;
  final int? brokenAt;
  final int length;
}

/// Memeriksa seluruh rantai: hash tiap block dan sambungan prev_hash.
ChainResult verifyChain(AppDb db) {
  final blocks = db.all('SELECT * FROM blocks ORDER BY idx');
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final expected = _calc(
      b['idx'] as int,
      b['timestamp'] as String,
      b['ticket_code'] as String,
      b['user_id'] as int,
      b['prev_hash'] as String,
    );
    if (b['hash'] != expected) {
      return ChainResult(valid: false, brokenAt: b['idx'] as int);
    }
    if (i > 0 && b['prev_hash'] != blocks[i - 1]['hash']) {
      return ChainResult(valid: false, brokenAt: b['idx'] as int);
    }
  }
  return ChainResult(valid: true, length: blocks.length);
}
