import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../services/time_zones.dart';

/// Konversi waktu event ke WIB, WITA, WIT, dan London.
class EventTimesCard extends StatelessWidget {
  const EventTimesCard({super.key, required this.startUtc, this.title = 'Event time'});
  final DateTime startUtc;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Icon(Icons.schedule, size: 20, color: AppColors.sun),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        for (final z in eventZones)
          Builder(builder: (_) {
            final c = convertToZone(startUtc, z.tzName);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: <Widget>[
                SizedBox(width: 64, child: Text(z.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.butter))),
                Expanded(child: Text(c.text, style: const TextStyle(fontSize: 13))),
                Text(c.abbr, style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              ]),
            );
          }),
      ]),
    );
  }
}
