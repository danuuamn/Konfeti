import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class PromosPage extends StatefulWidget {
  const PromosPage({super.key});
  @override
  State<PromosPage> createState() => _PromosPageState();
}

class _PromosPageState extends State<PromosPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Api.instance.get('/api/admin/promos') as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() {
    _f = _load();
  });

  Future<void> _toggle(Map<String, dynamic> p, bool on) async {
    try {
      await Api.instance.put('/api/admin/promos/${Uri.encodeComponent('${p['code']}')}', <String, Object?>{'active': on});
      if (mounted) toast(context, '${p['code']} ${on ? 'diaktifkan' : 'dinonaktifkan'}');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _reload();
  }

  Future<void> _dialog([Map<String, dynamic>? p]) async {
    final code = TextEditingController(text: p == null ? '' : '${p['code']}');
    final desc = TextEditingController(text: p == null ? '' : '${p['description']}');
    final pct = TextEditingController(text: p == null ? '' : '${p['discount_percent']}');
    final key = GlobalKey<FormState>();
    String? err;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dc) => StatefulBuilder(builder: (dc, setD) {
        return AlertDialog(
          title: Text(p == null ? 'Promo baru' : 'Ubah promo'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: key,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                FieldBox(
                  label: 'Kode (3-20: huruf, angka, - atau _)',
                  child: TextFormField(
                    controller: code,
                    enabled: p == null,
                    textCapitalization: TextCapitalization.characters,
                    style: t(14),
                    validator: (v) => RegExp(r'^[A-Za-z0-9_-]{3,20}$').hasMatch((v ?? '').trim()) ? null : 'Kode tidak valid',
                  ),
                ),
                const SizedBox(height: 12),
                FieldBox(
                  label: 'Deskripsi',
                  child: TextFormField(
                    controller: desc,
                    maxLength: 120,
                    style: t(14),
                    decoration: const InputDecoration(counterText: ''),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                  ),
                ),
                const SizedBox(height: 12),
                FieldBox(
                  label: 'Diskon (%) 1-90',
                  child: TextFormField(
                    controller: pct,
                    keyboardType: TextInputType.number,
                    style: t(14),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return n == null || n < 1 || n > 90 ? 'Angka 1-90' : null;
                    },
                  ),
                ),
                if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: t(13, color: C.danger))),
              ]),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: busy ? null : () => Navigator.pop(dc), child: const Text('Batal')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!key.currentState!.validate()) return;
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        if (p == null) {
                          await Api.instance.post('/api/admin/promos', <String, Object?>{
                            'code': code.text.trim().toUpperCase(),
                            'description': desc.text.trim(),
                            'discount_percent': int.parse(pct.text.trim()),
                          });
                        } else {
                          await Api.instance.put('/api/admin/promos/${Uri.encodeComponent('${p['code']}')}', <String, Object?>{
                            'description': desc.text.trim(),
                            'discount_percent': int.parse(pct.text.trim()),
                          });
                        }
                        if (dc.mounted) Navigator.pop(dc);
                        if (mounted) toast(context, 'Promo disimpan');
                        _reload();
                      } catch (e) {
                        setD(() {
                          busy = false;
                          err = errText(e);
                        });
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
        );
      }),
    );
    // tunggu animasi dialog selesai dulu, kalau tidak: assertion "_dependents.isEmpty"
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      code.dispose();
      desc.dispose();
      pct.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        PageHeader(
          title: 'Promos',
          subtitle: 'Kode promo tidak bisa dihapus, hanya dinonaktifkan.',
          actions: <Widget>[FilledButton.icon(onPressed: _dialog, icon: const Icon(Icons.add, size: 18), label: const Text('New promo'))],
        ),
        Expanded(
          child: FutureBody<List<Map<String, dynamic>>>(
            future: _f,
            onRetry: _reload,
            builder: (c, rows) => AdminTable<Map<String, dynamic>>(
              rows: rows,
              empty: 'Belum ada kode promo.',
              cols: <Col<Map<String, dynamic>>>[
                Col('Kode', (r) => cellText('${r['code']}', mono: true), width: 140),
                Col('Deskripsi', (r) => cellText('${r['description']}'), width: 260, flex: true),
                Col('Diskon', (r) => cellText('${r['discount_percent']}%', nums: true), width: 80, right: true),
                Col(
                  'Aktif',
                  (r) => Switch(value: r['active'] == 1 || r['active'] == true, onChanged: (v) => _toggle(r, v)),
                  width: 80,
                ),
                Col('', (r) => IconButton(tooltip: 'Ubah', onPressed: () => _dialog(r), icon: const Icon(Icons.edit_outlined, size: 18, color: C.sky)), width: 60, right: true),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
