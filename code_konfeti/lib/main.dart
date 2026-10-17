import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/favorites.dart';
import 'core/app_theme.dart';
import 'core/navigation.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/shell/main_shell.dart';
import 'services/sensor_service.dart';
import 'services/time_zones.dart';

// Accelerometer (darurat) hanya aktif saat login; gyroscope aktif di semua halaman sejak app dibuka.
void _syncSensors() => SensorService.instance.setEmergencyEnabled(Session.instance.loggedIn);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initTimeZones();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);

  ApiClient.instance.onUnauthorized = () {
    navigatorKey.currentState?.popUntil((r) => r.isFirst); // tutup halaman yang sedang terbuka
    Session.instance.logout();
  };
  await Favorites.load();
  await Session.instance.restore();
  SensorService.instance.startGyroscope();
  Session.instance.addListener(_syncSensors);
  _syncSensors();
  runApp(const KonfetiApp());
}

class KonfetiApp extends StatelessWidget {
  const KonfetiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Konfeti',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: Session.instance,
        builder: (context, _) => Session.instance.loggedIn ? const MainShell() : const LoginPage(),
      ),
    );
  }
}
