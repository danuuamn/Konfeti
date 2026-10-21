import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class BlockchainPage extends StatefulWidget {
  const BlockchainPage({super.key});
  @override
  State<BlockchainPage> createState() => _BlockchainPageState();
}

class _BlockchainPageState extends State<BlockchainPage> {
  late Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async =>
      Map<String, dynamic>.from(await Api.instance.get('/api/admin/blockchain', query: <String, String?>{'limit': '100'}) as Map);

  void _reload() => setState(() {
    _f = _load();
  });

  Widget _hash(String h) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: h));
          toast(context, 'Hash disalin');
        },
        child: Tooltip(message: '$h\n(ketuk untuk menyalin)', child: cellText(h.length > 8 ? h.substring(0, 8) : h, mono: true)),
      );

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        PageHeader(
          title: 'Blockchain',
          subtitle: 'Rantai hash SHA-256 untuk keaslian tiket. Hanya baca.',
          actions: <Widget>[OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 16), label: const Text('Verifikasi ulang'))],
        ),
        Expanded(
          child: FutureBody<Map<String, dynamic>>(
            future: _f,
            onRetry: _reload,
            builder: (c, d) {
              final valid = d['valid'] == true;
              final blocks = (d['blocks'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (valid ? C.success : C.danger).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: valid ? C.success : C.danger),
                  ),
                  child: Text(
                    valid ? 'Rantai valid, ${num0(d['length'])} blok' : 'Rantai rusak di blok #${d['broken_at']}',
                    style: t(14, w: FontWeight.w700, color: valid ? C.success : C.danger),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: AdminTable<Map<String, dynamic>>(
                    rows: blocks,
                    empty: 'Belum ada blok.',
                    cols: <Col<Map<String, dynamic>>>[
                      Col('#', (r) => cellText('${r['idx']}', nums: true), width: 60, right: true),
                      Col('Waktu', (r) => cellText(fmtDateTime(r['timestamp']), nums: true), width: 150),
                      Col('Kode tiket', (r) => cellText('${r['ticket_code']}', mono: true), width: 150, flex: true),
                      Col('User', (r) => cellText('${r['user_id']}', nums: true), width: 70, right: true),
                      Col('Prev hash', (r) => _hash('${r['prev_hash']}'), width: 110),
                      Col('Hash', (r) => _hash('${r['hash']}'), width: 110),
                    ],
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
