import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
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
  List<Ticket> _active = <Ticket>[];
  List<Ticket> _history = <Ticket>[];
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
        _active = tickets.where((t) => t.state == 'active').toList();
        _history = tickets.where((t) => t.state == 'history').toList();
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

  void _openTicket(Ticket t) {
    if (!t.canOpenDetail) {
      final d = t.startUtc.difference(DateTime.now().toUtc());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(d.isNegative
            ? 'This ticket is no longer available.'
            : 'Ticket details open when the event starts (in ${countdown(d)}).'),
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TicketDetailPage(ticket: t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        bottom: TabBar(controller: _tabs, tabs: <Widget>[
          Tab(text: 'Pending${_pending.isEmpty ? '' : ' (${_pending.length})'}'),
          const Tab(text: 'Active'),
          const Tab(text: 'History'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                )
              : TabBarView(controller: _tabs, children: <Widget>[
                  _list(_pending.map(_pendingCard).toList(), 'No pending payments.'),
                  _list(_active.map(_activeCard).toList(), 'No active tickets yet.\nBuy one from Home!'),
                  _list(_history.map(_historyCard).toList(), 'Past events will appear here.'),
                ]),
    );
  }

  Widget _list(List<Widget> items, String empty) {
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(children: <Widget>[
              const SizedBox(height: 120),
              Center(child: Text(empty, textAlign: TextAlign.center)),
            ])
          : ListView(padding: const EdgeInsets.all(16), children: items),
    );
  }

  Widget _pendingCard(Order o) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(o.title, style: Theme.of(context).textTheme.titleMedium),
          Text('${o.artist} • ${o.venueName}'),
          const SizedBox(height: 4),
          Text('${o.qty} ticket(s) • ${rupiah(o.grossAmount)}'),
          Text('Order ${o.orderId}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: () => _payNow(o), child: Text(o.isDemo ? 'Pay (demo)' : 'Pay now')),
          ),
        ]),
      ),
    );
  }

  Widget _activeCard(Ticket t) {
    final wib = convertToZone(t.startUtc, 'Asia/Jakarta');
    final untilStart = t.startUtc.difference(DateTime.now().toUtc());
    final badge = t.isLive ? 'LIVE NOW' : (untilStart.isNegative ? '' : 'Starts in ${countdown(untilStart)}');
    return Card(
      child: ListTile(
        onTap: () => _openTicket(t),
        leading: const Icon(Icons.confirmation_number, size: 32),
        title: Text(t.title),
        subtitle: Text('${t.venueName}\n${wib.text} ${wib.abbr}\n${t.code}'),
        isThreeLine: true,
        trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          if (badge.isNotEmpty)
            Text(badge,
                style: TextStyle(
                    color: t.isLive ? Colors.red : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }

  Widget _historyCard(Ticket t) {
    final wib = convertToZone(t.startUtc, 'Asia/Jakarta');
    return Card(
      child: ListTile(
        leading: const Icon(Icons.history, size: 32),
        title: Text(t.title),
        subtitle: Text('${t.venueName}\n${wib.text} ${wib.abbr}'),
        isThreeLine: true,
      ),
    );
  }
}
