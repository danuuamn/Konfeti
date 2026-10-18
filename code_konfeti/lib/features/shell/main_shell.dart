import 'package:flutter/material.dart';

import '../chat/chat_page.dart';
import '../fun/fun_page.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';
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
              ChatPage(),
              FunPage(),
              ProfilePage(),
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
