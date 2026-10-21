import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class BroadcastPage extends StatefulWidget {
  const BroadcastPage({super.key});
  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;
  int? _sentTo;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'Judul dan isi wajib diisi.');
      return;
    }
    final ok = await confirmDialog(context, title: 'Kirim ke semua user?', body: 'Notifikasi "$title" akan dikirim ke seluruh user terdaftar. Tidak bisa ditarik kembali.', confirmLabel: 'Kirim');
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
      _sentTo = null;
    });
    try {
      final r = await Api.instance.post('/api/admin/broadcast', <String, Object?>{'title': title, 'body': body}) as Map;
      if (!mounted) return;
      setState(() => _sentTo = asInt(r['sent_to']));
      _title.clear();
      _body.clear();
      toast(context, 'Terkirim ke ${r['sent_to']} user');
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: ListView(children: <Widget>[
        const PageHeader(title: 'Broadcast', subtitle: 'Kirim notifikasi ke semua user.'),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                FieldBox(
                  label: 'Judul (maks. 80)',
                  child: TextField(controller: _title, maxLength: 80, style: t(14), onChanged: (_) => setState(() {}), decoration: const InputDecoration(counterText: '')),
                ),
                Align(alignment: Alignment.centerRight, child: Text('${_title.text.length}/80', style: t(11, color: C.muted, nums: true))),
                const SizedBox(height: 8),
                FieldBox(
                  label: 'Isi (maks. 300)',
                  child: TextField(controller: _body, maxLength: 300, maxLines: 5, style: t(14), onChanged: (_) => setState(() {}), decoration: const InputDecoration(counterText: '')),
                ),
                Align(alignment: Alignment.centerRight, child: Text('${_body.text.length}/300', style: t(11, color: C.muted, nums: true))),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t(13, color: C.danger))),
                if (_sentTo != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Terkirim ke ${num0(_sentTo)} user.', style: t(13, color: C.success))),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink)) : const Text('Kirim'),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
