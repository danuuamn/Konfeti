import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});
  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  Timer? _timer;
  DateTime _updated = DateTime.now();
  String _filter = ''; // '' = semua, 'open' = belum ditangani

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Api.instance.get('/api/admin/emergency', query: <String, String?>{'limit': '100'}) as List;
    _updated = DateTime.now();
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _f = _load();
  });

  Future<void> _respond(Map<String, dynamic> r) async {
    final ok = await confirmDialog(
      context,
      title: 'Tandai ditangani?',
      body: 'Alert dari ${r['user_name']} akan ditandai sudah ditangani, dan pengirim menerima notifikasi bahwa staf sedang merespons.',
      confirmLabel: 'Tandai ditangani',
    );
    if (!ok) return;
    try {
      await Api.instance.post('/api/admin/emergency/${r['id']}/respond');
      if (!mounted) return;
      toast(context, 'Alert ditandai sudah ditangani.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      final stale = e is ApiException && e.status == 404 && e.message == 'Not found';
      toast(
        context,
        stale ? 'Server backend belum versi terbaru (endpoint respond tidak ada). Timpa admin.dart lalu restart server.' : errText(e),
        error: true,
      );
    }
  }

  Future<void> _map(Map<String, dynamic> r) async {
    if (r['latitude'] == null || r['longitude'] == null) return;
    final uri = Uri.parse('https://www.google.com/maps?q=${r['latitude']},${r['longitude']}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      toast(context, 'Tidak bisa membuka peta.', error: true);
    }
  }

  /// Tampilan HP: satu kartu per alert, tombol "Tanggapi" langsung terlihat.
  Widget _cards(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return EmptyBox(_filter == 'open' ? 'Tidak ada alert yang menunggu.' : 'Belum ada alert darurat.');
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _alertCard(rows[i]),
    );
  }

  Widget _alertCard(Map<String, dynamic> r) {
    final open = r['responded_at'] == null;
    final hasLoc = r['latitude'] != null && r['longitude'] != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? C.danger : C.line, width: open ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          open ? const StatusBadge('baru', color: C.danger) : const StatusBadge('ditangani', color: C.success),
          const Spacer(),
          Text(fmtDateTime(r['created_at']), style: t(12, color: C.textSoft, nums: true)),
        ]),
        const SizedBox(height: 10),
        Text('${r['user_name']}', style: t(16, w: FontWeight.w700)),
        Text('${r['user_email']}', style: t(12, color: C.textSoft)),
        const SizedBox(height: 8),
        Text('Event: ${r['event_title'] ?? '-'}', style: t(13)),
        Text('Tiket: ${r['ticket_code'] ?? '-'}', style: t(13, color: C.textSoft)),
        Text(hasLoc ? 'Lokasi: ${r['latitude']}, ${r['longitude']}' : 'Lokasi: tidak tersedia', style: t(13, color: C.textSoft)),
        if (!open) ...<Widget>[
          const SizedBox(height: 8),
          Text('Ditangani oleh ${r['responded_by_name'] ?? '-'} • ${fmtDateTime(r['responded_at'])}', style: t(12, color: C.success)),
        ],
        if (hasLoc || open) ...<Widget>[
          const SizedBox(height: 12),
          Row(children: <Widget>[
            if (hasLoc)
              Expanded(
                child: OutlinedButton.icon(onPressed: () => _map(r), icon: const Icon(Icons.map_outlined, size: 16), label: const Text('Open map')),
              ),
            if (hasLoc && open) const SizedBox(width: 8),
            if (open) Expanded(child: FilledButton(onPressed: () => _respond(r), child: const Text('Tanggapi'))),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        PageHeader(
          title: 'Emergency',
          subtitle: 'Diperbarui otomatis tiap 30 detik.',
          actions: <Widget>[OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh'))],
        ),
        Expanded(
          child: FutureBody<List<Map<String, dynamic>>>(
            future: _f,
            onRetry: _reload,
            builder: (c, all) {
              final openCount = all.where((r) => r['responded_at'] == null).length;
              final rows = _filter == 'open' ? all.where((r) => r['responded_at'] == null).toList() : all;
              final narrow = MediaQuery.sizeOf(context).width < 720; // HP: kartu, bukan tabel lebar
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
                  FilterChips(
                    options: const <String, String>{'': 'Semua', 'open': 'Belum ditangani'},
                    value: _filter,
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                  Text(
                    openCount == 0 ? 'Semua alert sudah ditangani.' : '$openCount alert belum ditangani',
                    style: t(13, w: FontWeight.w600, color: openCount == 0 ? C.success : C.danger),
                  ),
                ]),
              ),
              Expanded(
                child: narrow
                    ? _cards(rows)
                    : AdminTable<Map<String, dynamic>>(
                  rows: rows,
                  empty: _filter == 'open' ? 'Tidak ada alert yang menunggu.' : 'Belum ada alert darurat.',
                  cols: <Col<Map<String, dynamic>>>[
                    Col('Waktu', (r) => cellText(fmtDateTime(r['created_at']), nums: true), width: 150),
                    Col('User', (r) => cellTwoLine('${r['user_name']}', '${r['user_email']}'), width: 200, flex: true),
                    Col('Event', (r) => cellText('${r['event_title'] ?? '-'}'), width: 160, flex: true),
                    Col('Tiket', (r) => cellText('${r['ticket_code'] ?? '-'}', mono: true), width: 130),
                    Col('Lokasi', (r) => cellText(r['latitude'] == null ? '-' : '${r['latitude']}, ${r['longitude']}', nums: true), width: 160),
                    Col(
                      'Status',
                      (r) => r['responded_at'] == null
                          ? const StatusBadge('baru', color: C.danger)
                          : cellTwoLine('Ditangani', '${r['responded_by_name'] ?? ''} • ${fmtDateTime(r['responded_at'])}'),
                      width: 190,
                    ),
                    Col(
                      '',
                      (r) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        if (r['latitude'] != null) TextButton(onPressed: () => _map(r), child: const Text('Open map')),
                        if (r['responded_at'] == null) FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          onPressed: () => _respond(r),
                          child: const Text('Tanggapi'),
                        ),
                      ]),
                      width: 210,
                      right: true,
                    ),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('Diperbarui ${fmtDateTime(_updated.toUtc().toIso8601String())}', style: t(12, color: C.muted))),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
