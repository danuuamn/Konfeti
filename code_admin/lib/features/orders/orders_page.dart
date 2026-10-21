import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../widgets/ui.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String _status = '';
  String _q = '';
  int _offset = 0;
  late Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await Api.instance.get('/api/admin/orders', query: <String, String?>{
        'status': _status,
        'q': _q,
        'limit': '${AppConfig.pageSize}',
        'offset': '$_offset',
      }) as Map);

  void _reload({bool resetPage = false}) => setState(() {
        if (resetPage) _offset = 0;
        _f = _load();
      });

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const PageHeader(title: 'Orders'),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          FilterChips(
            options: const <String, String>{'': 'Semua', 'paid': 'Paid', 'pending': 'Pending', 'expired': 'Expired', 'failed': 'Failed'},
            value: _status,
            onChanged: (v) {
              _status = v;
              _reload(resetPage: true);
            },
          ),
          SearchField(
            hint: 'Order ID, nama, email',
            onChanged: (v) {
              _q = v;
              _reload(resetPage: true);
            },
          ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBody<Map<String, dynamic>>(
            future: _f,
            onRetry: _reload,
            builder: (c, d) {
              final rows = (d['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
              final total = asInt(d['total']);
              return Column(children: <Widget>[
                Expanded(
                  child: AdminTable<Map<String, dynamic>>(
                    rows: rows,
                    empty: 'Tidak ada order yang cocok.',
                    cols: <Col<Map<String, dynamic>>>[
                      Col('Order ID', (r) => cellText('${r['order_id']}', mono: true), width: 170),
                      Col('Pembeli', (r) => cellTwoLine('${r['user_name']}', '${r['user_email']}'), width: 200, flex: true),
                      Col('Event', (r) => cellText('${r['event_title']}'), width: 180, flex: true),
                      Col('Kategori', (r) => cellText('${r['tier_name'] ?? '-'}'), width: 100),
                      Col('Qty', (r) => cellText('${r['qty']}', nums: true), width: 50, right: true),
                      Col('Total', (r) => cellText(rp(r['gross_amount']), nums: true), width: 120, right: true),
                      Col('Status', (r) => StatusBadge('${r['status']}'), width: 90),
                      Col('Dibuat', (r) => cellText(fmtDateTime(r['created_at']), nums: true), width: 150),
                    ],
                  ),
                ),
                Pager(total: total, offset: _offset, limit: AppConfig.pageSize, onChange: (o) {
                  _offset = o;
                  _reload();
                }),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
