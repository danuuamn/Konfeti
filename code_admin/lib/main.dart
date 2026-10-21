import 'package:flutter/material.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
import 'features/shell/admin_shell.dart';
import 'features/shell/session_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.restore();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Konfeti Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: ListenableBuilder(
        listenable: Session.instance,
        builder: (context, _) => Session.instance.loggedIn ? const SessionGuard(child: AdminShell()) : const LoginPage(),
      ),
    );
  }
}
