import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';
import 'package:konfeti_backend/src/db.dart';
import 'package:konfeti_backend/src/env.dart';

/// Membuat akun admin (atau menjadikan akun yang sudah ada sebagai admin).
///
///   dart run bin/create_admin.dart --email admin@konfeti.id --name "Admin Konfeti"
///
/// Password diketik saat diminta (tidak tampil di layar) atau diambil dari ADMIN_PASSWORD
/// di environment. Password tidak pernah ditulis di kode atau di repo.
Future<void> main(List<String> args) async {
  Env.load();
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
  }

  final email = opt('email');
  final name = opt('name') ?? 'Admin';
  if (email == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    stderr.writeln('Usage: dart run bin/create_admin.dart --email <email> [--name "<nama>"]');
    exit(64);
  }

  final db = await AppDb.open();
  final existing = await db.one('SELECT id FROM users WHERE email=?', <Object?>[email]);
  if (existing != null) {
    await db.run("UPDATE users SET role='admin' WHERE email=?", <Object?>[email]);
    print('Existing user $email is now an admin (password unchanged).');
    await db.close();
    return;
  }

  var password = Platform.environment['ADMIN_PASSWORD'] ?? '';
  if (password.isEmpty) {
    stdout.write('Password (min. 8 characters): ');
    final hadEcho = stdin.echoMode;
    try {
      stdin.echoMode = false;
    } catch (_) {}
    password = stdin.readLineSync(encoding: utf8) ?? '';
    try {
      stdin.echoMode = hadEcho;
    } catch (_) {}
    stdout.writeln();
  }
  if (password.length < 8) {
    stderr.writeln('Password must be at least 8 characters.');
    exit(64);
  }

  final hash = await Isolate.run<String>(() => BCrypt.hashpw(password, BCrypt.gensalt()));
  await db.run(
    "INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,'admin')",
    <Object?>[name, email, hash],
  );
  await db.close();
  print('Admin $email created.');
}
