import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../chat/chat_page.dart';
import '../fun/fun_page.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';
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
              ChatPage(),
              FunPage(),
              ProfilePage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => ShellNav.tab.value = i,
            destinations: <NavigationDestination>[
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              const NavigationDestination(
                  icon: Icon(Icons.confirmation_number_outlined),
                  selectedIcon: Icon(Icons.confirmation_number),
                  label: 'My Tickets'),
              const NavigationDestination(
                  icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI Chat'),
              const NavigationDestination(
                  icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports), label: 'Fun'),
              NavigationDestination(
                icon: _profileIcon(Icons.person_outline),
                selectedIcon: _profileIcon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  /// Ikon Profile dengan badge jumlah notifikasi yang belum dibaca.
  Widget _profileIcon(IconData icon) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.unread,
      builder: (_, n, __) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(icon)),
    );
  }
}
