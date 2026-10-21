import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../widgets/ui.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Api.instance.get('/api/admin/logs', query: <String, String?>{'limit': '100'}) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() {
    _f = _load();
  });

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        PageHeader(
          title: 'Activity log',
          subtitle: 'Tindakan admin tercatat otomatis oleh server.',
          actions: <Widget>[OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh'))],
        ),
        Expanded(
          child: FutureBody<List<Map<String, dynamic>>>(
            future: _f,
            onRetry: _reload,
            builder: (c, rows) => AdminTable<Map<String, dynamic>>(
              rows: rows,
              empty: 'Belum ada aktivitas.',
              cols: <Col<Map<String, dynamic>>>[
                Col('Waktu', (r) => cellText(fmtDateTime(r['created_at']), nums: true), width: 150),
                Col('Admin', (r) => cellText('${r['admin_name']}'), width: 140),
                Col('Aksi', (r) => cellText('${r['action']}', mono: true), width: 150),
                Col('Target', (r) => cellText('${r['target']}', mono: true), width: 180),
                Col('Detail', (r) => cellText('${r['detail'] ?? ''}'), width: 240, flex: true),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
