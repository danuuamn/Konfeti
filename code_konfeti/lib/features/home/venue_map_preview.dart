import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';

/// Pratinjau lokasi venue (statis) + tombol buka peta.
/// TODO(Danu): peta interaktif flutter_map (posisi panggung, toilet, pos medis, dst.) bisa menggantikan kotak ini.
class VenueMapPreview extends StatelessWidget {
  const VenueMapPreview({super.key, required this.event});
  final Event event;

  Future<void> _openMaps() async {
    final lat = event.latitude, lng = event.longitude;
    if (lat == null || lng == null) return;
    await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = event.latitude != null && event.longitude != null;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(
          height: 140,
          width: double.infinity,
          child: Stack(alignment: Alignment.center, children: <Widget>[
            const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            const Icon(Icons.location_on, size: 48, color: AppColors.sun),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(event.venueName, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (hasCoords)
                  Text('${event.latitude!.toStringAsFixed(4)}, ${event.longitude!.toStringAsFixed(4)}',
                      style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              ]),
            ),
            if (hasCoords)
              FilledButton.icon(
                onPressed: _openMaps,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open map'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bgAlt);
    final grid = Paint()
      ..color = AppColors.skyFaint
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final road = Paint()
      ..color = const Color(0x558ACFF8)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.3, size.width, size.height * 0.45);
    canvas.drawPath(path, road);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
