import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../home/home_page.dart';
import '../tickets/my_tickets_page.dart';
import 'floating_nav.dart';
import 'shell_nav.dart';

/// Kerangka aplikasi dengan navigasi melayang 5 tab.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const List<NavItem> _items = <NavItem>[
    NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
    NavItem(icon: Icons.confirmation_number_outlined, selectedIcon: Icons.confirmation_number, label: 'My Tickets'),
    NavItem(icon: Icons.smart_toy_outlined, selectedIcon: Icons.smart_toy, label: 'AI Chat'),
    NavItem(icon: Icons.sports_esports_outlined, selectedIcon: Icons.sports_esports, label: 'Fun'),
    NavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ShellNav.tab,
      builder: (context, index, _) {
        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: index,
            children: const <Widget>[
              HomePage(),
              MyTicketsPage(),
              _Placeholder(title: 'AI Chatbot', icon: Icons.smart_toy_outlined),
              _Placeholder(title: 'Entertainment', icon: Icons.sports_esports_outlined),
              _ProfilePlaceholder(),
            ],
          ),
          bottomNavigationBar: FloatingNav(
            items: _items,
            selectedIndex: index,
            onSelected: (i) => ShellNav.tab.value = i,
          ),
        );
      },
    );
  }
}

/// Slot sementara untuk tab milik Danu. Ganti dengan halaman aslinya.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const <Widget>[RotateButton()]),
      body: AppBackground(
        child: Padding(
          padding: EdgeInsets.only(bottom: navBottomSpace(context)),
          child: EmptyState(icon: icon, title: '$title coming soon', subtitle: 'This feature is on its way.'),
        ),
      ),
    );
  }
}

class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder();

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;
    final name = user?['name']?.toString() ?? '-';
    final initial = name.trim().isNotEmpty && name != '-' ? name.trim()[0].toUpperCase() : '?';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: const <Widget>[RotateButton()]),
      body: AppBackground(
        child: Padding(
          padding: EdgeInsets.only(bottom: navBottomSpace(context)),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.glass,
                  border: Border.all(color: AppColors.sun, width: 2),
                ),
                child: Text(initial, style: AppText.display(size: 40, color: AppColors.sun)),
              ),
              const SizedBox(height: 16),
              Text(name, style: AppText.display(size: 26)),
              const SizedBox(height: 4),
              Text(user?['email']?.toString() ?? '', style: const TextStyle(color: AppColors.sky)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Session.instance.logout(),
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
