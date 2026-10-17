import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/event.dart';

/// Gambar event: pakai image_url jika ada, kalau tidak gradient biru dengan nama artis.
class EventBanner extends StatelessWidget {
  const EventBanner({super.key, required this.event, this.height});
  final Event event;
  final double? height;

  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF006199), Color(0xFF1C86C4)],
    <Color>[Color(0xFF004A77), Color(0xFF006199)],
    <Color>[Color(0xFF006199), Color(0xFF3FA3DC)],
    <Color>[Color(0xFF00507F), Color(0xFF2E8FCB)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[event.category.hashCode.abs() % _palettes.length];
    final url = event.imageUrl;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: url != null && url.startsWith('http')
          ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback())
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            event.isMultiArtist ? '${event.artists.first}\n+ ${event.artists.length - 1} more' : event.artist,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.sun, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
          ),
        ),
      );
}
