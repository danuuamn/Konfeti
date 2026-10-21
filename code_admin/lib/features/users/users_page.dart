import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../widgets/ui.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  String _q = '';
  int _offset = 0;
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Api.instance.get('/api/admin/users', query: <String, String?>{'q': _q, 'limit': '${AppConfig.pageSize}', 'offset': '$_offset'}) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload({bool resetPage = false}) => setState(() {
        if (resetPage) _offset = 0;
        _f = _load();
      });

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const PageHeader(title: 'Users'),
        SearchField(
          hint: 'Nama atau email',
          onChanged: (v) {
            _q = v;
            _reload(resetPage: true);
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBody<List<Map<String, dynamic>>>(
            future: _f,
            onRetry: _reload,
            builder: (c, rows) => Column(children: <Widget>[
              Expanded(
                child: AdminTable<Map<String, dynamic>>(
                  rows: rows,
                  empty: 'Tidak ada user yang cocok.',
                  cols: <Col<Map<String, dynamic>>>[
                    Col('Nama', (r) => cellTwoLine('${r['name']}', '${r['email']}'), width: 240, flex: true),
                    Col('Role', (r) => StatusBadge('${r['role']}'), width: 90),
                    Col('Tiket', (r) => cellText(num0(r['tickets']), nums: true), width: 70, right: true),
                    Col('Total belanja', (r) => cellText(rp(r['total_spent_idr']), nums: true), width: 130, right: true),
                    Col('Bergabung', (r) => cellText(fmtDateTime(r['created_at']), nums: true), width: 150),
                  ],
                ),
              ),
              PagerLite(offset: _offset, count: rows.length, limit: AppConfig.pageSize, onChange: (o) {
                _offset = o;
                _reload();
              }),
            ]),
          ),
        ),
      ]),
    );
  }
}
