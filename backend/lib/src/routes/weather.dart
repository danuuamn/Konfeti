import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env.dart';
import '../errors.dart';
import '../util.dart';
import '../web.dart';

Future<Map<String, dynamic>> _getJson(String url) async {
  final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200) throw ApiError(502, 'OpenWeatherMap status ${resp.statusCode}');
  final j = jsonDecode(utf8.decode(resp.bodyBytes));
  if (j is! Map<String, dynamic>) throw ApiError(502, 'Unexpected response from OpenWeatherMap');
  return j;
}

// Prediksi cuaca untuk event outdoor (OpenWeatherMap, key tersimpan di server)
void registerWeather(Router r) {
  r.get('/api/weather', (c) async {
    final key = Env.get('OPENWEATHER_API_KEY');
    if (key.isEmpty) {
      await c.json(503, <String, Object?>{'message': 'OPENWEATHER_API_KEY is not set in .env'});
      return;
    }

    final lat = numOf(c.query['lat']);
    final lon = numOf(c.query['lon']);
    if (lat == null || lon == null) {
      await c.json(400, <String, Object?>{'message': 'lat and lon are required'});
      return;
    }
    final atRaw = c.query['at'];
    final DateTime? at = (atRaw != null && atRaw.isNotEmpty) ? DateTime.tryParse(atRaw) : null;
    final double? days = at == null ? null : (at.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch) / 86400000;
    const base = 'https://api.openweathermap.org/data/2.5';
    final q = 'lat=$lat&lon=$lon&units=metric&appid=${Uri.encodeQueryComponent(key)}';

    try {
      if (at != null && days != null && days >= 0 && days <= 4.5) {
        final j = await _getJson('$base/forecast?$q');
        final list = j['list'] as List;
        final target = at.millisecondsSinceEpoch / 1000;
        Map<String, dynamic>? best;
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          if (best == null || ((m['dt'] as num) - target).abs() < ((best['dt'] as num) - target).abs()) best = m;
        }
        if (best == null) throw ApiError(502, 'Empty forecast');
        final main = best['main'] as Map;
        final wind = best['wind'] as Map;
        final weather = (best['weather'] as List).first as Map;
        final pop = best['pop'];
        final city = j['city'];
        await c.json(200, <String, Object?>{
          'kind': 'forecast',
          'time': isoMs(DateTime.fromMillisecondsSinceEpoch(((best['dt'] as num) * 1000).toInt(), isUtc: true)),
          'temp': main['temp'],
          'feels_like': main['feels_like'],
          'humidity': main['humidity'],
          'wind_speed': wind['speed'],
          'rain_probability': (((pop is num) ? pop : 0) * 100).round(),
          'description': weather['description'],
          'icon': weather['icon'],
          'city': city is Map ? city['name'] : null,
        });
        return;
      }

      final j = await _getJson('$base/weather?$q');
      final main = j['main'] as Map;
      final wind = j['wind'] as Map;
      final weather = (j['weather'] as List).first as Map;
      final name = j['name'];
      await c.json(200, <String, Object?>{
        'kind': 'current',
        'time': isoMs(DateTime.now()),
        'temp': main['temp'],
        'feels_like': main['feels_like'],
        'humidity': main['humidity'],
        'wind_speed': wind['speed'],
        'rain_probability': null,
        'description': weather['description'],
        'icon': weather['icon'],
        'city': (name is String && name.isNotEmpty) ? name : null,
        'note': 'Forecast is only available up to 5 days ahead. Showing current weather at the venue.',
      });
    } catch (e) {
      await c.json(502, <String, Object?>{'message': 'Weather service unavailable', 'detail': e.toString()});
    }
  }, auth: true);
}
