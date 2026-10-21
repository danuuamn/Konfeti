import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/brand.dart';
import '../blockchain/blockchain_page.dart';
import '../broadcast/broadcast_page.dart';
import '../checkin/checkin_page.dart';
import '../dashboard/dashboard_page.dart';
import '../emergency/emergency_page.dart';
import '../events/events_page.dart';
import '../feedback/feedback_page.dart';
import '../logs/logs_page.dart';
import '../orders/orders_page.dart';
import '../promos/promos_page.dart';
import '../users/users_page.dart';

class _Item {
  const _Item(this.id, this.label, this.icon, this.build);
  final String id;
  final String label;
  final IconData icon;
  final Widget Function() build;
}

class _Group {
  const _Group(this.title, this.items);
  final String title;
  final List<_Item> items;
}

final List<_Group> _groups = <_Group>[
  _Group('Overview', <_Item>[
    _Item('dashboard', 'Dashboard', Icons.space_dashboard_outlined, () => const DashboardPage()),
  ]),
  _Group('Operations', <_Item>[
    _Item('checkin', 'Check-in', Icons.qr_code_scanner, () => const CheckinPage()),
    _Item('events', 'Events', Icons.event_outlined, () => const EventsPage()),
    _Item('orders', 'Orders', Icons.receipt_long_outlined, () => const OrdersPage()),
    _Item('emergency', 'Emergency', Icons.warning_amber_outlined, () => const EmergencyPage()),
  ]),
  _Group('Customers', <_Item>[
    _Item('users', 'Users', Icons.people_outline, () => const UsersPage()),
    _Item('promos', 'Promos', Icons.sell_outlined, () => const PromosPage()),
    _Item('broadcast', 'Broadcast', Icons.campaign_outlined, () => const BroadcastPage()),
    _Item('feedback', 'Feedback', Icons.chat_bubble_outline, () => const FeedbackPage()),
  ]),
  _Group('System', <_Item>[
    _Item('blockchain', 'Blockchain', Icons.link, () => const BlockchainPage()),
    _Item('logs', 'Activity log', Icons.history, () => const LogsPage()),
  ]),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  String _current = 'dashboard';
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();
  int _alerts = 0; // alert darurat baru sejak halaman Emergency terakhir dibuka
  int _seenMaxId = 0;
  bool _seenInit = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _checkAlerts();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _checkAlerts());
    adminNav.addListener(_onNavRequest);
  }

  /// Permintaan pindah menu dari halaman lain (mis. tombol di dashboard).
  void _onNavRequest() {
    final id = adminNav.value;
    if (id == null || !mounted) return;
    if (_groups.any((g) => g.items.any((i) => i.id == id))) _go(id);
  }

  @override
  void dispose() {
    adminNav.removeListener(_onNavRequest);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkAlerts() async {
    try {
      final rows = await Api.instance.get('/api/admin/emergency', query: <String, String?>{'limit': '50'}) as List;
      final ids = rows.map((r) => ((r as Map)['id'] as num).toInt()).toList();
      final maxId = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
      if (!_seenInit) {
        _seenInit = true;
        _seenMaxId = maxId; // alert yang sudah ada saat app dibuka dianggap sudah dilihat
      }
      final fresh = ids.where((i) => i > _seenMaxId).length;
      if (mounted && fresh != _alerts) setState(() => _alerts = fresh);
    } catch (_) {}
  }

  void _go(String id) {
    if (id == 'emergency') {
      _alerts = 0;
      _seenInit = false; // tandai semua yang ada sekarang sebagai sudah dilihat pada polling berikutnya
      _checkAlerts();
    }
    setState(() => _current = id);
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
  }

  _Item get _item => _groups.expand((g) => g.items).firstWhere((i) => i.id == _current);

  Widget _nav() {
    final u = Session.instance.user!;
    return Container(
      width: 232,
      decoration: const BoxDecoration(color: C.bg, border: Border(right: BorderSide(color: C.line))),
      child: SafeArea(
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(children: <Widget>[
              const BrandLogo(size: 30),
              const SizedBox(width: 10),
              Text('Konfeti', style: t(17, w: FontWeight.w800, color: C.sun)),
              const SizedBox(width: 6),
              Text('Admin', style: t(17, w: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: <Widget>[
              for (final g in _groups) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                  child: Text(g.title.toUpperCase(), style: t(11, w: FontWeight.w700, color: C.muted)),
                ),
                for (final i in g.items) _navTile(i),
              ],
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: <Widget>[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(13, w: FontWeight.w600)),
                  Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(11, color: C.textSoft)),
                ]),
              ),
              IconButton(tooltip: 'Logout', onPressed: () => Session.instance.logout(), icon: const Icon(Icons.logout, size: 18, color: C.sky)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _navTile(_Item i) {
    final sel = i.id == _current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _go(i.id),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: sel ? C.primary.withAlpha(64) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Row(children: <Widget>[
            Icon(i.icon, size: 18, color: sel ? C.sun : C.sky),
            const SizedBox(width: 10),
            Expanded(child: Text(i.label, style: t(13, w: FontWeight.w600, color: sel ? C.sun : Colors.white))),
            if (i.id == 'emergency' && _alerts > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: C.danger, borderRadius: BorderRadius.circular(8)),
                child: Text('$_alerts', style: t(11, w: FontWeight.w700, color: C.ink, nums: true)),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final page = KeyedSubtree(key: ValueKey<String>(_current), child: _item.build());
    if (wide) {
      return Scaffold(body: Row(children: <Widget>[_nav(), Expanded(child: page)]));
    }
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(_item.label, style: t(16, w: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffold.currentState?.openDrawer()),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      drawer: Drawer(backgroundColor: C.bg, child: _nav()),
      body: page,
    );
  }
}
