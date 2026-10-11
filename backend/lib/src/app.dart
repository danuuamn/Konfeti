import 'dart:io';

import 'db.dart';
import 'env.dart';
import 'routes/auth.dart';
import 'routes/chat.dart';
import 'routes/emergency.dart';
import 'routes/events.dart';
import 'routes/feedback.dart';
import 'routes/notifications.dart';
import 'routes/orders.dart';
import 'routes/promos.dart';
import 'routes/rates.dart';
import 'routes/spotify.dart';
import 'routes/tickets.dart';
import 'routes/weather.dart';
import 'web.dart';

/// Menjalankan server Konfeti. Dipanggil dari bin/server.dart.
Future<void> runServer() async {
  Env.load();
  if (!Env.has('JWT_SECRET')) {
    stderr.writeln('JWT_SECRET is missing. Copy .env.example to .env and fill it in.');
    exit(1);
  }

  await Directory('${Directory.current.path}${Platform.pathSeparator}uploads${Platform.pathSeparator}avatars')
      .create(recursive: true);

  final db = AppDb.open();
  final router = Router();

  router.get('/api/health', (c) async {
    await c.json(200, <String, Object?>{
      'status': 'ok',
      'dev': Env.devRoutes,
      'features': <String, Object?>{
        'midtrans': Env.has('MIDTRANS_SERVER_KEY'),
        'gemini': Env.has('GEMINI_API_KEY'),
        'spotify': Env.has('SPOTIFY_CLIENT_ID') && Env.has('SPOTIFY_CLIENT_SECRET'),
        'weather': Env.has('OPENWEATHER_API_KEY'),
      },
    });
  });

  registerAuth(router, db);
  registerEvents(router, db);
  registerOrders(router, db);
  registerTickets(router, db);
  registerNotifications(router, db);
  registerPromos(router, db);
  registerFeedback(router, db);
  registerEmergency(router, db);
  registerRates(router);
  registerWeather(router);
  registerSpotify(router, db);
  registerChat(router, db);

  final port = int.tryParse(Env.get('PORT', '3000')) ?? 3000;
  await AppServer(router).serve(port);
}
