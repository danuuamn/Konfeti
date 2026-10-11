import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Sensor 1: Accelerometer. Memicu [onShake] hanya jika terjadi [requiredShakes] guncangan kuat
/// dalam [window] (default 3 guncangan dalam 2 detik) supaya tidak terpicu tanpa sengaja.
class ShakeDetector {
  ShakeDetector({
    required this.onShake,
    this.thresholdG = 2.7,
    this.requiredShakes = 3,
    this.window = const Duration(seconds: 2),
    this.minGap = const Duration(milliseconds: 250),
  });

  final void Function() onShake;
  final double thresholdG; // gaya total dalam satuan g (diam = ~1 g)
  final int requiredShakes;
  final Duration window;
  final Duration minGap;

  StreamSubscription<AccelerometerEvent>? _sub;
  final List<DateTime> _hits = <DateTime>[];

  void start() {
    _sub ??= accelerometerEventStream().listen((e) {
      final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.80665;
      if (g < thresholdG) return;
      final now = DateTime.now();
      if (_hits.isNotEmpty && now.difference(_hits.last) < minGap) return;
      _hits.add(now);
      _hits.removeWhere((t) => now.difference(t) > window);
      if (_hits.length >= requiredShakes) {
        _hits.clear();
        onShake();
      }
    }, onError: (Object _) {/* perangkat tanpa sensor: abaikan */});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _hits.clear();
  }
}
