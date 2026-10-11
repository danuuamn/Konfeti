import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hitung mundur sebelum sinyal darurat dikirim. Pop(true) = kirim, pop(false) = dibatalkan.
class EmergencyCountdownDialog extends StatefulWidget {
  const EmergencyCountdownDialog({super.key, this.seconds = 5});
  final int seconds;

  @override
  State<EmergencyCountdownDialog> createState() => _EmergencyCountdownDialogState();
}

class _EmergencyCountdownDialogState extends State<EmergencyCountdownDialog> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        if (mounted) Navigator.pop(context, true);
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
        title: const Text('Sending emergency alert'),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text('$_left', style: Theme.of(context).textTheme.displayMedium?.copyWith(color: Colors.red)),
          const SizedBox(height: 8),
          const Text('Event staff will receive your location. Tap cancel if this was a mistake.',
              textAlign: TextAlign.center),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ],
      ),
    );
  }
}
