import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../core/formatters.dart';
import '../../models/event.dart';
import '../../services/local_db.dart';
import '../../services/time_zones.dart';
import '../shell/shell_nav.dart';
import 'ticket_detail_page.dart';

/// My Tickets: tab Pending Payment, Active, History.
class MyTicketsPage extends StatefulWidget {
  const MyTicketsPage({super.key});

  @override
  State<MyTicketsPage> createState() => _MyTicketsPageState();
}

class _MyTicketsPageState extends State<MyTicketsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<Order> _pending = <Order>[];
  List<TicketGroup> _active = <TicketGroup>[];
  List<TicketGroup> _history = <TicketGroup>[];
  bool _loading = true;
  bool _offline = false; // true = yang tampil adalah salinan tersimpan di HP
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    ShellNav.tab.addListener(_onShellTab);
    ShellNav.ticketsSubTab.addListener(_onSubTab);
    _load();
    // Selama ada pembayaran tertunda, cek status tiap 6 detik (menunggu webhook Midtrans).
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && ShellNav.tab.value == 1 && _pending.isNotEmpty) _load(silent: true);
    });
  }

  @override
  void dispose() {
    ShellNav.tab.removeListener(_onShellTab);
    ShellNav.ticketsSubTab.removeListener(_onSubTab);
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _onShellTab() {
    if (ShellNav.tab.value == 1) _load(silent: true); // refresh tiap kali tab dibuka
  }

  void _onSubTab() => _tabs.animateTo(ShellNav.ticketsSubTab.value);

  Future<(List<Order>, List<Ticket>)> _fetch() async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      ApiClient.instance.get('/api/orders'),
      ApiClient.instance.get('/api/tickets'),
    ]);
    final orders =
        (results[0] as List).map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final tickets =
        (results[1] as List).map((e) => Ticket.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    // Simpan salinan tiket di HP supaya QR tetap bisa dibuka saat tidak ada sinyal.
    unawaited(LocalDb.instance
        .putCache(currentUserId(), 'tickets', jsonEncode(results[1]))
        .catchError((Object _) {}));
    return (orders, tickets);
  }

  /// Muat tiket dari salinan lokal (dipakai saat server tidak terjangkau). Mengembalikan false bila belum ada salinan.
  Future<bool> _loadFromCache() async {
    try {
      final raw = await LocalDb.instance.getCache(currentUserId(), 'tickets');
      if (raw == null) return false;
      final tickets = (jsonDecode(raw) as List)
          .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return true;
      setState(() {
        _pending = <Order>[]; // status pembayaran harus dari server, jadi tidak ditampilkan offline
        _active = groupTickets(tickets.where((t) => t.state == 'active').toList());
        _history = groupTickets(tickets.where((t) => t.state == 'history').toList());
        _offline = true;
        _error = null;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      var (orders, tickets) = await _fetch();
      // Tanya Midtrans langsung untuk order pending, supaya tidak bergantung pada webhook.
      final toSync = orders.where((o) => o.status == 'pending' && !o.isDemo).toList();
      if (toSync.isNotEmpty) {
        await Future.wait(toSync.map((o) =>
            ApiClient.instance.post('/api/orders/${o.orderId}/sync').then<dynamic>((v) => v).catchError((_) => null)));
        (orders, tickets) = await _fetch();
      }
      if (!mounted) return;
      setState(() {
        _pending = orders.where((o) => o.status == 'pending').toList();
        // 1 kartu per pemesanan (order), meskipun isinya beberapa tiket
        _active = groupTickets(tickets.where((t) => t.state == 'active').toList());
        _history = groupTickets(tickets.where((t) => t.state == 'history').toList());
        _offline = false;
        _error = null;
      });
    } catch (e) {
      // Offline: tampilkan tiket tersimpan. Hanya error jaringan (status 0) yang memakai cache.
      final offlineErr = e is ApiException && e.status == 0;
      final usedCache = offlineErr && await _loadFromCache();
      if (!usedCache && mounted && !silent) setState(() => _error = e.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _payNow(Order o) async {
    try {
      if (o.isDemo) {
        await ApiClient.instance.post('/api/orders/dev/simulate-paid/${o.orderId}');
        await _load(silent: true);
        ShellNav.ticketsSubTab.value = 1;
      } else if (o.redirectUrl != null) {
        await launchUrl(Uri.parse(o.redirectUrl!), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openTicket(TicketGroup t) {
    if (!t.canOpenDetail) {
      final d = t.startUtc.difference(DateTime.now().toUtc());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(d.isNegative
            ? 'This ticket is no longer available.'
            : 'Ticket details open when the event starts (in ${countdown(d)}).'),
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TicketDetailPage(group: t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        actions: const <Widget>[RotateButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: TabBar(
                controller: _tabs,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                indicator: BoxDecoration(color: AppColors.sun, borderRadius: BorderRadius.circular(999)),
                labelColor: AppColors.ink,
                unselectedLabelColor: AppColors.sky,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                splashBorderRadius: BorderRadius.circular(999),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: <Widget>[
                  Tab(text: 'Pending${_pending.isEmpty ? '' : ' (${_pending.length})'}'),
                  const Tab(text: 'Active'),
                  const Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AppBackground(
        child: Column(children: <Widget>[
          if (_offline) _offlineBanner(),
          Expanded(
            child: _loading
                ? _skeletonList()
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : TabBarView(controller: _tabs, children: <Widget>[
                        _list(_pending.map(_pendingCard).toList(), Icons.hourglass_empty, 'No pending payments',
                            'Orders waiting for payment show up here.'),
                        _list(_active.map(_activeCard).toList(), Icons.confirmation_number_outlined,
                            'No active tickets yet', 'Buy one from Home!'),
                        _list(_history.map(_historyCard).toList(), Icons.history, 'No past events',
                            'Past events will appear here.'),
                      ]),
          ),
        ]),
      ),
    );
  }

  Widget _offlineBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: const Row(children: <Widget>[
        Icon(Icons.cloud_off_outlined, size: 16, color: AppColors.sun),
        SizedBox(width: 8),
        Expanded(
          child: Text('Offline: showing tickets saved on this phone. Pull down to refresh when you are back online.',
              style: TextStyle(color: AppColors.sky, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _skeletonList() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(height: 104)),
        Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(height: 104)),
        Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(height: 104)),
      ],
    );
  }

  Widget _list(List<Widget> items, IconData icon, String title, String subtitle) {
    return RefreshIndicator(
      color: AppColors.ink,
      backgroundColor: AppColors.sun,
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: <Widget>[
              const SizedBox(height: 72),
              SizedBox(height: 320, child: EmptyState(icon: icon, title: title, subtitle: subtitle)),
            ])
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, navBottomSpace(context)),
              children: items,
            ),
    );
  }

  Widget _pendingCard(Order o) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Row(children: <Widget>[
          Tag('AWAITING PAYMENT', icon: Icons.hourglass_top),
        ]),
        const SizedBox(height: 10),
        Text(o.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${o.artist} • ${o.venueName}', style: const TextStyle(color: AppColors.sky, fontSize: 13)),
        const SizedBox(height: 8),
        Text('${o.qty} ticket(s) • ${rupiah(o.grossAmount)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('Order ${o.orderId}', style: const TextStyle(color: AppColors.skyDim, fontSize: 11)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: () => _payNow(o), child: Text(o.isDemo ? 'Pay (demo)' : 'Pay now')),
        ),
      ]),
    );
  }

  Widget _dateBlock(DateTime startUtc) {
    final p = zoneParts(startUtc, 'Asia/Jakarta');
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(p.month.toUpperCase(),
            style: const TextStyle(color: AppColors.sky, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        Text(p.day, style: AppText.display(size: 24, color: AppColors.sun, weight: FontWeight.w700, height: 1.1)),
      ]),
    );
  }

  Widget _activeCard(TicketGroup t) {
    final p = zoneParts(t.startUtc, 'Asia/Jakarta');
    final untilStart = t.startUtc.difference(DateTime.now().toUtc());
    final badge = untilStart.isNegative ? '' : 'Starts in ${countdown(untilStart)}';
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _openTicket(t),
      child: Row(children: <Widget>[
        _dateBlock(t.startUtc),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text('${t.venueName}\n${p.time} ${p.abbr}', style: const TextStyle(color: AppColors.sky, fontSize: 12)),
            const SizedBox(height: 8),
            Tag('${t.count} ticket${t.count > 1 ? 's' : ''}', icon: Icons.confirmation_number_outlined),
          ]),
        ),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
          if (t.isLive)
            const Tag('LIVE NOW', icon: Icons.circle, color: AppColors.danger)
          else if (badge.isNotEmpty)
            Text(badge, style: const TextStyle(color: AppColors.butter, fontWeight: FontWeight.w800, fontSize: 11)),
          const SizedBox(height: 4),
          const Icon(Icons.chevron_right, color: AppColors.sky),
        ]),
      ]),
    );
  }

  Widget _historyCard(TicketGroup t) {
    final p = zoneParts(t.startUtc, 'Asia/Jakarta');
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0x660E2340),
      child: Opacity(
        opacity: 0.8,
        child: Row(children: <Widget>[
          _dateBlock(t.startUtc),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text('${t.venueName}\n${p.date} • ${p.time} ${p.abbr}', style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              const SizedBox(height: 8),
              Tag('${t.count} ticket${t.count > 1 ? 's' : ''}', outlined: true),
            ]),
          ),
          const Icon(Icons.check_circle_outline, color: AppColors.skyDim),
        ]),
      ),
    );
  }
}
