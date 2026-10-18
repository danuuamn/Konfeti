import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class NavItem {
  const NavItem({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Navigasi bawah berbentuk pill kaca yang melayang. Item aktif = lingkaran kuning + label.
class FloatingNav extends StatelessWidget {
  const FloatingNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: AppColors.glassHigh,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(children: <Widget>[for (var i = 0; i < items.length; i++) _item(i)]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final selected = i == selectedIndex;
    final item = items[i];
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onSelected(i),
          child: SizedBox(
            height: height,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selected
                    ? Column(
                        key: ValueKey<String>('active-$i'),
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(color: AppColors.sun, shape: BoxShape.circle),
                            child: Icon(item.selectedIcon, size: 22, color: AppColors.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(item.label,
                              maxLines: 1,
                              style: const TextStyle(color: AppColors.sun, fontSize: 10, fontWeight: FontWeight.w700)),
                        ],
                      )
                    : Icon(item.icon, key: ValueKey<String>('idle-$i'), size: 24, color: AppColors.sky),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
