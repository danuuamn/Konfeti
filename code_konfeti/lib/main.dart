import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/shell/main_shell.dart';
import 'services/time_zones.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initTimeZones();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);

  ApiClient.instance.onUnauthorized = () {
    navigatorKey.currentState?.popUntil((r) => r.isFirst); // tutup halaman yang sedang terbuka
    Session.instance.logout();
  };
  await Session.instance.restore();
  runApp(const KonfetiApp());
}

class KonfetiApp extends StatelessWidget {
  const KonfetiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Konfeti',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C3AED)),
      ),
      home: ListenableBuilder(
        listenable: Session.instance,
        builder: (context, _) => Session.instance.loggedIn ? const MainShell() : const LoginPage(),
      ),
    );
  }
}
