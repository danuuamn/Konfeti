import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/event.dart';

/// Gambar event: pakai image_url jika ada, kalau tidak gradient biru dengan nama artis.
/// `heroTag` (opsional) membuat gambar beranimasi ke halaman detail. Tag harus unik per layar.
class EventBanner extends StatelessWidget {
  const EventBanner({super.key, required this.event, this.height, this.heroTag});
  final Event event;
  final double? height;
  final Object? heroTag;

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
    final banner = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: url != null && url.startsWith('http')
          ? Image.network(
              url,
              fit: BoxFit.cover,
              semanticLabel: event.artist,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => wasSynchronouslyLoaded
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 300),
                      child: child,
                    ),
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
    return heroTag == null ? banner : Hero(tag: heroTag!, child: banner);
  }

  Widget _fallback() => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            event.isMultiArtist ? '${event.artists.first}\n+ ${event.artists.length - 1} more' : event.artist,
            textAlign: TextAlign.center,
            style: AppText.display(size: 22, color: AppColors.sun, weight: FontWeight.w700, height: 1.2),
          ),
        ),
      );
}
