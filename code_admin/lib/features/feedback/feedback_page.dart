import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../widgets/ui.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Api.instance.get('/api/admin/feedback', query: <String, String?>{'limit': '100'}) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() {
    _f = _load();
  });

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const PageHeader(title: 'Feedback'),
        Expanded(
          child: FutureBody<List<Map<String, dynamic>>>(
            future: _f,
            onRetry: _reload,
            builder: (c, rows) => AdminTable<Map<String, dynamic>>(
              rows: rows,
              empty: 'Belum ada feedback.',
              cols: <Col<Map<String, dynamic>>>[
                Col('Waktu', (r) => cellText(fmtDateTime(r['created_at']), nums: true), width: 150),
                Col('User', (r) => cellTwoLine('${r['user_name']}', '${r['user_email']}'), width: 200),
                Col('Rating', (r) => cellText('${r['rating']}/5', nums: true), width: 70, right: true),
                Col('Pesan', (r) => Tooltip(message: '${r['message']}', child: cellText('${r['message']}')), width: 300, flex: true),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
