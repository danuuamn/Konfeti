import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'event_detail_page.dart';
import 'event_form_page.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  String _status = '';
  String _q = '';
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Api.instance.get('/api/admin/events', query: <String, String?>{'status': _status, 'q': _q}) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() {
    _f = _load();
  });

  Future<void> _open(Map<String, dynamic> e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EventDetailPage(eventId: asInt(e['id']))));
    if (mounted) _reload();
  }

  Future<void> _create() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute<int>(builder: (_) => const EventFormPage()));
    if (!mounted) return;
    _reload();
    if (id != null) _open(<String, dynamic>{'id': id});
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        PageHeader(
          title: 'Events',
          actions: <Widget>[FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add, size: 18), label: const Text('New event'))],
        ),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          FilterChips(
            options: const <String, String>{'': 'Semua', 'active': 'Active', 'draft': 'Draft', 'cancelled': 'Cancelled'},
            value: _status,
            onChanged: (v) {
              _status = v;
              _reload();
            },
          ),
          SearchField(
            hint: 'Judul atau artis',
            onChanged: (v) {
              _q = v;
              _reload();
            },
          ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBody<List<Map<String, dynamic>>>(
            future: _f,
            onRetry: _reload,
            builder: (c, rows) => AdminTable<Map<String, dynamic>>(
              rows: rows,
              empty: 'Tidak ada event yang cocok.',
              onTap: _open,
              cols: <Col<Map<String, dynamic>>>[
                Col('Event', (r) => cellTwoLine('${r['title']}', '${r['artist'] ?? ''}'), width: 220, flex: true),
                Col('Venue', (r) => cellText('${r['venue_name'] ?? '-'}'), width: 180),
                Col('Mulai', (r) => cellText(fmtDateTime(r['start_time_utc']), nums: true), width: 150),
                Col('Harga mulai', (r) => cellText(rp(r['price_idr']), nums: true), width: 120, right: true),
                Col('Terjual / stok', (r) => cellText('${num0(r['tickets_sold'])} / ${num0(r['stock'])}', nums: true), width: 110, right: true),
                Col('Status', (r) => StatusBadge('${r['status']}'), width: 100),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
