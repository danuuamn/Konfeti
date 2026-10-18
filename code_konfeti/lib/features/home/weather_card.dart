import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/time_zones.dart';

/// Prakiraan cuaca di venue (OpenWeatherMap lewat backend /api/weather) untuk event outdoor.
/// Forecast hanya tersedia sampai ~5 hari ke depan; selebihnya server membalas cuaca saat ini.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key, required this.event});
  final Event event;

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = widget.event;
    if (e.latitude == null || e.longitude == null) {
      setState(() {
        _loading = false;
        _error = 'This venue has no coordinates.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await ApiClient.instance.get('/api/weather', query: <String, String>{
        'lat': '${e.latitude}',
        'lon': '${e.longitude}',
        'at': e.startUtc.toIso8601String(),
      }) as Map;
      if (mounted) setState(() => _data = Map<String, dynamic>.from(j));
    } catch (err) {
      if (mounted) {
        setState(() => _error = (err is ApiException && err.status == 503)
            ? 'Weather data is not available right now.'
            : err.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          : _error != null
              ? Row(children: <Widget>[
                  const Icon(Icons.cloud_off_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ])
              : _content(),
    );
  }

  Widget _content() {
    final d = _data!;
    final temp = (d['temp'] as num?)?.round();
    final feels = (d['feels_like'] as num?)?.round();
    final humidity = (d['humidity'] as num?)?.round();
    final wind = (d['wind_speed'] as num?)?.toDouble();
    final rain = (d['rain_probability'] as num?)?.round();
    final icon = d['icon']?.toString();
    final description = _capitalize(d['description']?.toString() ?? '');
    final city = d['city']?.toString();
    final note = d['note']?.toString();
    final isForecast = d['kind'] == 'forecast';

    String title = isForecast ? 'Forecast at showtime' : 'Current weather at the venue';
    if (isForecast && d['time'] != null) {
      final t = DateTime.tryParse(d['time'].toString());
      if (t != null) {
        final c = convertToZone(t.toUtc(), 'Asia/Jakarta');
        title = 'Forecast • ${c.text} ${c.abbr}';
      }
    }

    String? advice;
    if (rain != null && rain >= 50) {
      advice = 'High chance of rain. Bring a raincoat or poncho.';
    } else if (temp != null && temp >= 32) {
      advice = 'It will be hot. Bring water and sun protection.';
    } else if (isForecast) {
      advice = 'Good conditions for an outdoor show.';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: const TextStyle(color: AppColors.sky, fontSize: 12.5)),
      const SizedBox(height: 8),
      Row(children: <Widget>[
        if (icon != null && icon.isNotEmpty)
          Image.network(
            'https://openweathermap.org/img/wn/$icon@2x.png',
            width: 72,
            height: 72,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 72,
              height: 72,
              child: Icon(Icons.wb_cloudy_outlined, size: 40, color: AppColors.sky),
            ),
          )
        else
          const SizedBox(width: 72, height: 72, child: Icon(Icons.wb_cloudy_outlined, size: 40, color: AppColors.sky)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(
              temp == null ? '-' : '$temp°C',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
            ),
            Text(description, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (feels != null || (city != null && city.isNotEmpty))
              Text(
                <String>[
                  if (feels != null) 'Feels like $feels°C',
                  if (city != null && city.isNotEmpty) city,
                ].join(' • '),
                style: const TextStyle(color: AppColors.sky, fontSize: 12),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
        if (humidity != null) Tag('Humidity $humidity%', icon: Icons.water_drop_outlined),
        if (wind != null) Tag('Wind ${wind.toStringAsFixed(1)} m/s', icon: Icons.air),
        if (rain != null) Tag('Rain $rain%', icon: Icons.umbrella_outlined),
      ]),
      if (advice != null) ...<Widget>[
        const SizedBox(height: 10),
        Text(advice, style: const TextStyle(color: AppColors.butter, fontWeight: FontWeight.w600, height: 1.3)),
      ],
      if (!isForecast && note != null && note.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text(note, style: const TextStyle(color: AppColors.skyDim, fontSize: 11.5, height: 1.3)),
      ],
    ]);
  }
}
