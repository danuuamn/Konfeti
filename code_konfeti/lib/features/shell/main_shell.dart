import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../home/home_page.dart';
import '../tickets/my_tickets_page.dart';
import 'shell_nav.dart';

/// Kerangka aplikasi dengan bottom navigation 5 tab.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ShellNav.tab,
      builder: (context, index, _) {
        return Scaffold(
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => ShellNav.tab.value = i,
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.confirmation_number_outlined),
                  selectedIcon: Icon(Icons.confirmation_number),
                  label: 'My Tickets'),
              NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI Chat'),
              NavigationDestination(
                  icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports), label: 'Fun'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
            ],
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
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text('$title coming soon', style: Theme.of(context).textTheme.titleMedium),
        ]),
      ),
    );
  }
}

class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder();

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(user?['name']?.toString() ?? '-', style: Theme.of(context).textTheme.titleLarge),
          Text(user?['email']?.toString() ?? ''),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => Session.instance.logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ]),
      ),
    );
  }
}
