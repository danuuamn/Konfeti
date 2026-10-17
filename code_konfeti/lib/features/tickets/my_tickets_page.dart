import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../core/formatters.dart';
import '../../models/event.dart';
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
    return (orders, tickets);
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
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
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
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.sun,
          unselectedLabelColor: AppColors.sky,
          indicatorColor: AppColors.sun,
          dividerColor: AppColors.skyFaint,
          tabs: <Widget>[
            Tab(text: 'Pending${_pending.isEmpty ? '' : ' (${_pending.length})'}'),
            const Tab(text: 'Active'),
            const Tab(text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
                    FilledButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                )
              : TabBarView(controller: _tabs, children: <Widget>[
                  _list(_pending.map(_pendingCard).toList(), 'No pending payments.', Icons.hourglass_empty),
                  _list(_active.map(_activeCard).toList(), 'No active tickets yet.\nBuy one from Home!', Icons.confirmation_number_outlined),
                  _list(_history.map(_historyCard).toList(), 'Past events will appear here.', Icons.history),
                ]),
    );
  }

  Widget _list(List<Widget> items, String empty, IconData icon) {
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(children: <Widget>[
              const SizedBox(height: 120),
              Icon(icon, size: 56, color: AppColors.skyDim),
              const SizedBox(height: 12),
              Center(child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sky))),
            ])
          : ListView(padding: const EdgeInsets.all(16), children: items),
    );
  }

  Widget _pendingCard(Order o) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Tag('AWAITING PAYMENT', icon: Icons.hourglass_top),
        ]),
        const SizedBox(height: 8),
        Text(o.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text('${o.artist} • ${o.venueName}', style: const TextStyle(color: AppColors.sky, fontSize: 13)),
        const SizedBox(height: 6),
        Text('${o.qty} ticket(s) • ${rupiah(o.grossAmount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Order ${o.orderId}', style: const TextStyle(color: AppColors.sky, fontSize: 11)),
        const SizedBox(height: 10),
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
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(p.month.toUpperCase(), style: const TextStyle(color: AppColors.sky, fontSize: 11, fontWeight: FontWeight.w600)),
        Text(p.day, style: const TextStyle(color: AppColors.sun, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1)),
      ]),
    );
  }

  Widget _activeCard(TicketGroup t) {
    final p = zoneParts(t.startUtc, 'Asia/Jakarta');
    final untilStart = t.startUtc.difference(DateTime.now().toUtc());
    final badge = t.isLive ? 'LIVE NOW' : (untilStart.isNegative ? '' : 'Starts in ${countdown(untilStart)}');
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
            const SizedBox(height: 6),
            Tag('${t.count} ticket${t.count > 1 ? 's' : ''}', icon: Icons.confirmation_number_outlined),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (badge.isNotEmpty)
            Text(badge,
                style: TextStyle(
                    color: t.isLive ? const Color(0xFFFF6B6B) : AppColors.butter, fontWeight: FontWeight.w700, fontSize: 11)),
          const Icon(Icons.chevron_right, color: AppColors.sky),
        ]),
      ]),
    );
  }

  Widget _historyCard(TicketGroup t) {
    final p = zoneParts(t.startUtc, 'Asia/Jakarta');
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.bgAlt,
      child: Row(children: <Widget>[
        _dateBlock(t.startUtc),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text('${t.venueName}\n${p.date} • ${p.time} ${p.abbr}', style: const TextStyle(color: AppColors.sky, fontSize: 12)),
            const SizedBox(height: 6),
            Tag('${t.count} ticket${t.count > 1 ? 's' : ''}', outlined: true),
          ]),
        ),
        const Icon(Icons.check_circle_outline, color: AppColors.skyDim),
      ]),
    );
  }
}
