import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Hiasan confetti datar (tanpa gradient/blur): potongan kertas kecil dengan warna palet Konfeti.
/// Posisinya acak tapi tetap (seed), jadi tidak berubah tiap rebuild.
class ConfettiPainter extends CustomPainter {
  const ConfettiPainter({this.seed = 7, this.count = 46});
  final int seed;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    const colors = <Color>[C.sun, C.sky, C.butter, Colors.white];
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final paint = Paint()..color = colors[rnd.nextInt(colors.length)].withAlpha(rnd.nextBool() ? 190 : 90);
      final s = 5 + rnd.nextDouble() * 9;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rnd.nextDouble() * math.pi);
      final kind = rnd.nextInt(3);
      if (kind == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 1.8, height: s * 0.7), const Radius.circular(1.5)),
          paint,
        );
      } else if (kind == 1) {
        canvas.drawCircle(Offset.zero, s * 0.4, paint);
      } else {
        final path = Path()
          ..moveTo(0, -s * 0.6)
          ..lineTo(s * 0.55, s * 0.45)
          ..lineTo(-s * 0.55, s * 0.45)
          ..close();
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.seed != seed || old.count != count;
}

/// Latar berwarna solid (primary) dengan confetti di atasnya, dipakai di login dan banner dashboard.
class ConfettiBanner extends StatelessWidget {
  const ConfettiBanner({super.key, required this.child, this.seed = 7, this.count = 46, this.radius = 0, this.color = C.primary});
  final Widget child;
  final int seed;
  final int count;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: color,
        child: Stack(children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: ConfettiPainter(seed: seed, count: count))),
          child,
        ]),
      ),
    );
  }
}

/// Logo Konfeti (aset yang sama dengan app user).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/konfeti_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.confirmation_number_rounded, size: size * 0.8, color: C.sun),
    );
  }
}
