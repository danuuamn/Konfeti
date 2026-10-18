import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/sensor_service.dart';
import 'app_theme.dart';
import 'glass.dart';

// Supaya file yang sudah meng-import widgets.dart otomatis mendapat GlassCard, AppBackground, dll.
export 'glass.dart';

/// Kartu standar design system (sekarang kaca): translucent + border tipis. Bisa diklik (ripple).
/// Parameter lama dipertahankan; semua pemanggil lama otomatis berganti tampilan.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = 20,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: padding,
      margin: margin,
      color: color,
      radius: radius,
      child: child,
    );
  }
}

/// Chip kategori: aktif = kuning + teks gelap, tidak aktif = kaca + border tipis.
class CategoryPill extends StatelessWidget {
  const CategoryPill({super.key, required this.label, required this.selected, this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.ink : AppColors.sky;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: ShapeDecoration(
            color: selected ? AppColors.sun : AppColors.glass,
            shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.sun : AppColors.glassBorder)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (icon != null) ...<Widget>[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

/// Tag/badge kecil untuk kategori, LIVE NOW, status, dll. `color` opsional untuk mengganti warna isi.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.outlined = false, this.color});
  final String label;
  final IconData? icon;
  final bool outlined;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? AppColors.sky : AppColors.ink;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : (color ?? AppColors.butter),
        borderRadius: BorderRadius.circular(999),
        border: outlined ? Border.all(color: AppColors.glassBorder) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (icon != null) ...<Widget>[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.3)),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.live = false, this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 12)});
  final String title;
  final bool live;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: <Widget>[
        if (live) ...<Widget>[
          const Icon(Icons.circle, size: 10, color: AppColors.danger),
          const SizedBox(width: 8),
        ],
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Tombol bulat kaca untuk di atas gambar hero (back, favorite, rotate). Target sentuh 48 dp.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onTap, this.color = Colors.white, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: const Color(0x800A192F),
            shape: const CircleBorder(side: BorderSide(color: AppColors.glassBorder)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 22)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol rotasi layar manual (cadangan gyroscope), tersedia di semua halaman utama.
class RotateButton extends StatelessWidget {
  const RotateButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Rotate screen',
      icon: const Icon(Icons.screen_rotation),
      onPressed: SensorService.instance.toggleOrientation,
    );
  }
}
