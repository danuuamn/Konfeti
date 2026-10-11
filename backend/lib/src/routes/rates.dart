import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util.dart';
import '../web.dart';

// Kurs cadangan (perkiraan) jika API publik tidak bisa dihubungi. Nilai = 1 IDR dalam mata uang tsb.
const Map<String, double> _fallback = <String, double>{
  'USD': 0.000061,
  'EUR': 0.000056,
  'JPY': 0.0092,
  'SGD': 0.000079,
  'MYR': 0.00027,
};

Map<String, Object?>? _cache;
DateTime _cacheExpires = DateTime.fromMillisecondsSinceEpoch(0);

void registerRates(Router r) {
  r.get('/api/rates', (c) async {
    final cached = _cache;
    if (cached != null && _cacheExpires.isAfter(DateTime.now())) {
      await c.json(200, cached);
      return;
    }
    try {
      final resp = await http.get(Uri.parse('https://open.er-api.com/v6/latest/IDR')).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) throw Exception('status ${resp.statusCode}');
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      if (j is! Map || j['result'] != 'success' || j['rates'] is! Map) throw Exception('bad response');
      final live = j['rates'] as Map;
      final rates = <String, Object?>{'IDR': 1};
      _fallback.forEach((code, fb) {
        final v = live[code];
        rates[code] = (v is num && v != 0) ? v : fb;
      });
      final data = <String, Object?>{
        'base': 'IDR',
        'source': 'live',
        'rates': rates,
        'updated_at': isoMs(DateTime.now()),
      };
      _cache = data;
      _cacheExpires = DateTime.now().add(const Duration(hours: 1));
      await c.json(200, data);
    } catch (_) {
      await c.json(200, <String, Object?>{
        'base': 'IDR',
        'source': 'fallback',
        'rates': <String, Object?>{'IDR': 1, ..._fallback},
        'updated_at': isoMs(DateTime.now()),
      });
    }
  });
}
