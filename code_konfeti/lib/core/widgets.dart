import 'package:flutter/material.dart';

import '../services/sensor_service.dart';
import 'app_theme.dart';

/// Kartu standar design system: latar #006199, sudut membulat, border tipis. Bisa diklik (ripple).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? AppColors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.whiteFaint),
        ),
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Pill kategori: aktif = kuning + teks gelap, tidak aktif = outline biru muda.
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
      color: selected ? AppColors.sun : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.sun : AppColors.sky)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (icon != null) ...<Widget>[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

/// Tag/badge kecil (kuning pucat) untuk kategori, LIVE NOW, dll.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.outlined = false});
  final String label;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? AppColors.sky : AppColors.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : AppColors.butter,
        borderRadius: BorderRadius.circular(20),
        border: outlined ? Border.all(color: AppColors.sky) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (icon != null) ...<Widget>[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.live = false, this.padding = const EdgeInsets.fromLTRB(16, 22, 16, 10)});
  final String title;
  final bool live;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: <Widget>[
        if (live) ...<Widget>[
          const Icon(Icons.circle, size: 10, color: Color(0xFFFF4D4D)),
          const SizedBox(width: 8),
        ],
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Tombol bulat transparan untuk di atas gambar hero (back, favorite, rotate).
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
      child: Material(
        color: const Color(0x990A192F),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: color, size: 22)),
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
