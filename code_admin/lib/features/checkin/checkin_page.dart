import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key});
  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late Future<List<Map<String, dynamic>>> _events = _loadEvents();
  int? _eventId;
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<List<Map<String, dynamic>>> _loadEvents() async {
    final r = await Api.instance.get('/api/admin/events', query: <String, String?>{'status': 'active'}) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool checkIn, String? override}) async {
    final code = (override ?? _code.text).trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, Object?>{'code': code, if (_eventId != null) 'event_id': _eventId};
      final res = await Api.instance.post(checkIn ? '/api/admin/tickets/check-in' : '/api/admin/tickets/verify', body);
      if (!mounted) return;
      final map = Map<String, dynamic>.from(res as Map);
      setState(() {
        _result = map;
      });
      final ok = map['status'] == 'checked_in' || map['status'] == 'valid';
      ok ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
      _code.clear();
      _focus.requestFocus();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute<String>(builder: (_) => const _ScannerPage()));
    if (code != null && mounted) {
      _code.text = code;
      await _submit(checkIn: true, override: code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: ListView(children: <Widget>[
        const PageHeader(title: 'Check-in', subtitle: 'Scan atau ketik kode tiket di pintu masuk.'),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  FieldBox(
                    label: 'Event',
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _events,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Row(children: <Widget>[
                            Expanded(child: Text(errText(snap.error!), style: t(13, color: C.danger))),
                            TextButton(onPressed: () => setState(() {
    _events = _loadEvents();
  }), child: const Text('Retry')),
                          ]);
                        }
                        final list = snap.data ?? const <Map<String, dynamic>>[];
                        return DropdownButtonFormField<int?>(
                          initialValue: _eventId,
                          isExpanded: true,
                          dropdownColor: C.panel,
                          style: t(14),
                          hint: Text(snap.connectionState == ConnectionState.done ? 'Semua event (tidak dibatasi)' : 'Memuat...', style: t(14, color: C.muted)),
                          items: <DropdownMenuItem<int?>>[
                            const DropdownMenuItem<int?>(value: null, child: Text('Semua event (tidak dibatasi)')),
                            ...list.map((e) => DropdownMenuItem<int?>(value: asInt(e['id']), child: Text('${e['title']}', overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) => setState(() => _eventId = v),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  FieldBox(
                    label: 'Kode tiket',
                    child: TextField(
                      controller: _code,
                      focusNode: _focus,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 18, color: Colors.white, letterSpacing: 1),
                      onSubmitted: (_) => _submit(checkIn: true),
                      decoration: const InputDecoration(hintText: 'Tempel atau ketik kode'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    FilledButton(
                      onPressed: _busy ? null : () => _submit(checkIn: true),
                      child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink)) : const Text('Check in'),
                    ),
                    OutlinedButton(onPressed: _busy ? null : () => _submit(checkIn: false), child: const Text('Hanya verifikasi')),
                    if (!kIsWeb)
                      OutlinedButton.icon(onPressed: _busy ? null : _scan, icon: const Icon(Icons.qr_code_scanner, size: 18), label: const Text('Scan QR')),
                  ]),
                ]),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: t(13, color: C.danger))),
              if (_result != null) ...<Widget>[const SizedBox(height: 16), _ResultPanel(result: _result!)],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final status = '${result['status']}';
    final Color color;
    final String title;
    switch (status) {
      case 'checked_in':
        color = C.success;
        title = 'Check-in berhasil';
      case 'valid':
        color = C.success;
        title = 'Tiket valid';
      case 'already_used':
        color = C.sun;
        title = 'Sudah dipakai';
      case 'wrong_event':
        color = C.danger;
        title = 'Event tidak sesuai';
      case 'event_cancelled':
        color = C.danger;
        title = 'Event dibatalkan';
      case 'invalid_chain':
        color = C.danger;
        title = 'Gagal verifikasi blockchain';
      case 'not_found':
        color = C.danger;
        title = 'Tiket tidak ditemukan';
      default:
        color = C.danger;
        title = 'Ditolak';
    }
    final ticket = result['ticket'] is Map ? Map<String, dynamic>.from(result['ticket'] as Map) : null;
    final note = status == 'valid' ? 'Belum ditandai masuk. Tekan "Check in" untuk menandai.' : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: color, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: t(22, w: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text('${result['message'] ?? ''}', style: t(14)),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: t(13, color: C.textSoft))),
        if (ticket != null) ...<Widget>[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _kv('Pemilik', '${ticket['owner_name']}  (${ticket['owner_email']})'),
          _kv('Event', '${ticket['event_title']}'),
          _kv('Kategori', '${ticket['tier_name'] ?? '-'}'),
          if (ticket['holder_name'] != null) ...<Widget>[
            const SizedBox(height: 4),
            Text('Data pembawa tiket (cocokkan dengan KTP)', style: t(12, w: FontWeight.w700, color: C.sun)),
            const SizedBox(height: 8),
            _kv('Nama', '${ticket['holder_name']}'),
            _kv('NIK', _maskNik('${ticket['holder_nik'] ?? ''}'), mono: true),
            _kv('Umur / gender', '${ticket['holder_age'] ?? '-'} th • ${ticket['holder_gender'] ?? '-'}'),
            const Divider(height: 20),
          ],
          _kv('Kode', '${ticket['ticket_code']}', mono: true),
          if (ticket['used_at'] != null) _kv('Check-in', '${fmtDateTime(ticket['used_at'])}${ticket['checked_in_by_name'] != null ? ' oleh ${ticket['checked_in_by_name']}' : ''}'),
          if (result['block_index'] != null) _kv('Blok', '#${result['block_index']}'),
        ],
      ]),
    );
  }

  /// NIK ditampilkan sebagian saja (4 digit awal dan akhir) supaya tidak terbaca orang di sekitar petugas.
  static String _maskNik(String nik) => nik.length < 8 ? nik : '${nik.substring(0, 4)}••••••••${nik.substring(nik.length - 4)}';

  Widget _kv(String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          SizedBox(width: 84, child: Text(k, style: t(13, color: C.textSoft))),
          Expanded(child: Text(v, style: mono ? const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white) : t(13, w: FontWeight.w600))),
        ]),
      );
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();
  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final MobileScannerController _c = MobileScannerController(formats: const <BarcodeFormat>[BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Scan QR tiket', style: t(16, w: FontWeight.w700)),
        actions: <Widget>[IconButton(tooltip: 'Senter', icon: const Icon(Icons.flash_on, size: 20), onPressed: () => _c.toggleTorch())],
      ),
      body: Stack(fit: StackFit.expand, children: <Widget>[
        MobileScanner(
          controller: _c,
          onDetect: (capture) {
            if (_done) return;
            final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (raw == null || raw.isEmpty) return;
            _done = true;
            Navigator.pop(context, raw);
          },
        ),
        Center(child: Container(width: 240, height: 240, decoration: BoxDecoration(border: Border.all(color: C.sun, width: 2), borderRadius: BorderRadius.circular(12)))),
        Positioned(left: 0, right: 0, bottom: 32, child: Center(child: Text('Arahkan kamera ke QR pada tiket', style: t(13)))),
      ]),
    );
  }
}
