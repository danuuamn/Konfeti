import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Ruang kosong di bawah list agar isi tidak tertutup navigasi melayang
/// (tinggi nav 64 + jarak 12 + napas 16, ditambah inset sistem di bawah layar).
double navBottomSpace(BuildContext context) => 92 + MediaQuery.viewPaddingOf(context).bottom;

/// Kartu kaca: kilau tipis dari kiri-atas, border halus, dan (opsional) blur nyata di belakangnya.
/// `blur` dipakai untuk elemen yang jumlahnya sedikit (panel, form, tab, nav); untuk banyak item
/// berurutan cukup tanpa blur supaya tetap ringan di HP biasa.
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

  /// Jika diisi, kartu memakai warna solid ini (tanpa kilau).
  final Color? color;
  final double radius;
  final bool highlight;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: color,
        gradient: color == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.glassSheen, AppColors.glass],
              )
            : null,
        border: Border.all(color: highlight ? AppColors.glow : AppColors.glassBorder, width: highlight ? 1.2 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
    if (blur) {
      box = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: box),
      );
    }
    if (highlight) {
      box = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x59006199), blurRadius: 24, spreadRadius: -4)],
        ),
        child: box,
      );
    }
    return Padding(padding: margin, child: box);
  }
}

/// Chip kecil berlatar kaca untuk di atas foto (kategori, jarak, status).
class GlassChip extends StatelessWidget {
  const GlassChip(this.label, {super.key, this.icon, this.iconColor});
  final String label;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: const Color(0x660A192F),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (icon != null) ...<Widget>[Icon(icon, size: 14, color: iconColor ?? AppColors.sky), const SizedBox(width: 5)],
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Logo Konfeti tanpa kotak: gambar transparan dengan pendar putih yang mengikuti bentuk logo
/// (bukan latar putih persegi), supaya garis biru tua logo tetap terbaca di latar navy.
/// Berkas gambar: assets/images/konfeti_logo.png (rasio ~1.2 : 1).
class KonfetiLogo extends StatelessWidget {
  const KonfetiLogo({super.key, this.size = 56});

  /// Tinggi logo; lebarnya mengikuti rasio gambar.
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size * 1.2;
    Widget img() => Image.asset(
          'assets/images/konfeti_logo.png',
          width: w,
          height: size,
          fit: BoxFit.contain,
          semanticLabel: 'Konfeti logo',
          errorBuilder: (_, __, ___) =>
              Icon(Icons.confirmation_number_rounded, size: size * 0.7, color: AppColors.sun),
        );
    return SizedBox(
      width: w,
      height: size,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: <Widget>[
        // pendar putih lebar, lalu inti pendar yang lebih rapat
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: size * 0.22, sigmaY: size * 0.22),
          child: ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x73FFFFFF), BlendMode.srcIn), child: img()),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: size * 0.05, sigmaY: size * 0.05),
          child: ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x8CFFFFFF), BlendMode.srcIn), child: img()),
        ),
        img(),
      ]),
    );
  }
}

/// Latar layar: navy dengan tiga pendar warna palet (biru dan sedikit kuning) agar kaca punya sesuatu
/// untuk dibiaskan. Hanya memakai primary dan sun yang sudah ada.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: <Widget>[
      const Positioned(top: -150, left: -130, child: _Glow(size: 440, color: AppColors.primary, alpha: 140)),
      const Positioned(top: 320, right: -170, child: _Glow(size: 400, color: AppColors.primary, alpha: 80)),
      const Positioned(bottom: -140, left: -70, child: _Glow(size: 340, color: AppColors.sun, alpha: 26)),
      child,
    ]);
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color, required this.alpha});
  final double size;
  final Color color;
  final int alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: <Color>[color.withAlpha(alpha), color.withAlpha(0)]),
        ),
      ),
    );
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
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.glassSheen, AppColors.glass],
              ),
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
