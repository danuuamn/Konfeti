import 'package:flutter/material.dart';

import '../../services/time_zones.dart';

/// Konversi waktu event ke WIB, WITA, WIT, dan London.
class EventTimesCard extends StatelessWidget {
  const EventTimesCard({super.key, required this.startUtc, this.title = 'Event time'});
  final DateTime startUtc;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          for (final z in eventZones)
            Builder(builder: (_) {
              final c = convertToZone(startUtc, z.tzName);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: <Widget>[
                  SizedBox(width: 64, child: Text(z.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(child: Text(c.text)),
                  Text(c.abbr, style: theme.textTheme.bodySmall),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
