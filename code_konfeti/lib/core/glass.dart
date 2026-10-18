import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Ruang kosong di bawah list agar isi tidak tertutup navigasi melayang
/// (tinggi nav 64 + jarak 12 + napas 16, ditambah inset sistem di bawah layar).
double navBottomSpace(BuildContext context) => 92 + MediaQuery.viewPaddingOf(context).bottom;

/// Kartu kaca: isi translucent + border tipis. `blur` hanya untuk elemen kecil/jarang
/// (nav, hero, panel CTA); jangan dipakai di banyak item list karena berat di HP biasa.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = 20,
    this.highlight = false,
    this.blur = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;
  final bool highlight;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget card = Material(
      color: color ?? AppColors.glass,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: highlight ? AppColors.glow : AppColors.glassBorder, width: highlight ? 1.2 : 1),
      ),
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    if (blur) {
      card = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: card),
      );
    }
    if (highlight) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x59006199), blurRadius: 24, spreadRadius: -4)],
        ),
        child: card,
      );
    }
    return Padding(padding: margin, child: card);
  }
}

/// Latar layar: navy dengan cahaya biru halus di pojok kiri atas.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: <Widget>[
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.9, -1.0),
              radius: 1.1,
              colors: <Color>[Color(0x660B3A66), Color(0x000B3A66)],
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}

/// Placeholder berkedip saat loading (pengganti spinner layar penuh).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height, this.width, this.radius = 20});
  final double? height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = still ? 0.5 : Curves.easeInOut.transform(_c.value);
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.glass, AppColors.glassHigh, t),
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: AppColors.glassBorder),
          ),
        );
      },
    );
  }
}

/// Keadaan kosong: ikon besar + judul (+ keterangan).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glass,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, size: 40, color: AppColors.skyDim),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sky, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}

/// Keadaan error: pesan + tombol Try again.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.danger),
          const SizedBox(height: 12),
          const Text('Something went wrong', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.sky, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      ),
    );
  }
}
