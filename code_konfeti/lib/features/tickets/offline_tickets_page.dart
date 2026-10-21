import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/local_db.dart';
import '../../services/time_zones.dart';
import 'ticket_detail_page.dart';

/// Tiket yang tersimpan di HP, bisa dibuka dari halaman login tanpa sinyal.
/// Hanya baca: tidak ada pembelian, pembayaran, atau pembaruan data di sini.
class OfflineTicketsPage extends StatefulWidget {
  const OfflineTicketsPage({super.key});

  /// True bila ada salinan tiket di HP (dipakai untuk menampilkan tombol di halaman login).
  static Future<bool> hasSavedTickets() async {
    try {
      final uid = await LocalDb.instance.lastTicketCacheUser();
      if (uid == null) return false;
      return (await LocalDb.instance.getCache(uid, 'tickets')) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  State<OfflineTicketsPage> createState() => _OfflineTicketsPageState();
}

class _OfflineTicketsPageState extends State<OfflineTicketsPage> {
  List<TicketGroup> _active = <TicketGroup>[];
  List<TicketGroup> _history = <TicketGroup>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = await LocalDb.instance.lastTicketCacheUser();
      final raw = uid == null ? null : await LocalDb.instance.getCache(uid, 'tickets');
      if (raw == null) {
        if (mounted) setState(() => _error = 'No saved tickets on this phone.');
        return;
      }
      final tickets = (jsonDecode(raw) as List)
          .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _active = groupTickets(tickets.where((t) => t.state == 'active').toList());
        _history = groupTickets(tickets.where((t) => t.state == 'history').toList());
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Saved tickets could not be read.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(TicketGroup t) {
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

  Widget _card(TicketGroup t, {required bool past}) {
    final p = zoneParts(t.startUtc, 'Asia/Jakarta');
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: past ? null : () => _open(t),
      child: Opacity(
        opacity: past ? 0.7 : 1,
        child: Row(children: <Widget>[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text('${t.venueName}\n${p.date} • ${p.time} ${p.abbr}',
                  style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              const SizedBox(height: 8),
              Tag('${t.count} ticket${t.count > 1 ? 's' : ''}',
                  icon: past ? null : Icons.confirmation_number_outlined, outlined: past),
            ]),
          ),
          Icon(past ? Icons.check_circle_outline : Icons.chevron_right, color: AppColors.sky),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved tickets')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Row(children: <Widget>[
                        Icon(Icons.cloud_off_outlined, size: 16, color: AppColors.sun),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Offline copy. Sign in when you have a connection to refresh your tickets.',
                              style: TextStyle(color: AppColors.sky, fontSize: 12)),
                        ),
                      ]),
                    ),
                    if (_active.isEmpty && _history.isEmpty)
                      const EmptyState(
                        icon: Icons.confirmation_number_outlined,
                        title: 'No saved tickets',
                        subtitle: 'Open My Tickets once while online to save them.',
                      ),
                    for (final t in _active) _card(t, past: false),
                    if (_history.isNotEmpty) ...<Widget>[
                      const SectionHeader('Past events', padding: EdgeInsets.fromLTRB(0, 12, 0, 10)),
                      for (final t in _history) _card(t, past: true),
                    ],
                  ]),
      ),
    );
  }
}
