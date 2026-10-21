import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'event_form_page.dart';

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({super.key, required this.eventId});
  final int eventId;
  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Future<Map<String, dynamic>> _f = _load();
  late Future<List<Map<String, dynamic>>> _tf = _loadTickets();
  String _ticketFilter = '';
  String _ticketQ = '';

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await Api.instance.get('/api/admin/events/${widget.eventId}') as Map);

  Future<List<Map<String, dynamic>>> _loadTickets() async {
    final r = await Api.instance.get('/api/admin/events/${widget.eventId}/tickets') as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() {
        _f = _load();
        _tf = _loadTickets();
      });

  Future<void> _edit(Map<String, dynamic> e) async {
    final r = await Navigator.of(context).push<int>(MaterialPageRoute<int>(builder: (_) => EventFormPage(event: e)));
    if (r != null && mounted) _reload();
  }

  Future<void> _setStatus(Map<String, dynamic> e, String status) async {
    final cancel = status == 'cancelled';
    final ok = await confirmDialog(
      context,
      title: cancel ? 'Batalkan event?' : 'Ubah status?',
      body: cancel
          ? '"${e['title']}" akan dibatalkan dan semua pembeli yang sudah membayar menerima notifikasi pembatalan. Tindakan ini tidak mengembalikan dana otomatis.'
          : 'Status "${e['title']}" menjadi $status.',
      confirmLabel: cancel ? 'Batalkan event' : 'Ubah',
      danger: cancel,
    );
    if (!ok) return;
    try {
      await Api.instance.put('/api/admin/events/${e['id']}', <String, Object?>{'status': status});
      if (mounted) toast(context, 'Status diubah ke $status');
      _reload();
    } catch (err) {
      if (mounted) toast(context, errText(err), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await confirmDialog(context, title: 'Hapus event?', body: 'Event "${e['title']}" dan semua kategori tiketnya dihapus permanen.', confirmLabel: 'Hapus', danger: true);
    if (!ok) return;
    try {
      await Api.instance.delete('/api/admin/events/${e['id']}');
      if (!mounted) return;
      toast(context, 'Event dihapus');
      Navigator.pop(context);
    } on ApiException catch (err) {
      if (!mounted) return;
      if (err.status == 409) {
        final cancel = await confirmDialog(context, title: 'Tidak bisa dihapus', body: '${err.message}\n\nBatalkan event ini saja?', confirmLabel: 'Batalkan event', danger: true);
        if (cancel) {
          try {
            await Api.instance.put('/api/admin/events/${e['id']}', <String, Object?>{'status': 'cancelled'});
            if (mounted) toast(context, 'Event dibatalkan');
            _reload();
          } catch (e2) {
            if (mounted) toast(context, errText(e2), error: true);
          }
        }
      } else {
        toast(context, err.message, error: true);
      }
    }
  }

  Future<void> _tierDialog(Map<String, dynamic> event, [Map<String, dynamic>? tier]) async {
    final name = TextEditingController(text: tier == null ? '' : '${tier['name']}');
    final desc = TextEditingController(text: tier == null ? '' : '${tier['description'] ?? ''}');
    final price = TextEditingController(text: tier == null ? '' : '${tier['price_idr']}');
    final stock = TextEditingController(text: tier == null ? '' : '${tier['stock']}');
    final key = GlobalKey<FormState>();
    String? err;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dc) => StatefulBuilder(builder: (dc, setD) {
        String? intRule(String? v) {
          final n = int.tryParse((v ?? '').trim());
          return n == null || n < 0 ? 'Angka >= 0' : null;
        }

        return AlertDialog(
          title: Text(tier == null ? 'Kategori tiket baru' : 'Ubah kategori'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: key,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                FieldBox(label: 'Nama *', child: TextFormField(controller: name, maxLength: 40, style: t(14), validator: (v) => (v ?? '').trim().isEmpty ? 'Wajib diisi' : null, decoration: const InputDecoration(counterText: ''))),
                const SizedBox(height: 12),
                FieldBox(label: 'Deskripsi', child: TextFormField(controller: desc, maxLength: 200, style: t(14), decoration: const InputDecoration(counterText: ''))),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(child: FieldBox(label: 'Harga (IDR) *', child: TextFormField(controller: price, keyboardType: TextInputType.number, style: t(14), validator: intRule))),
                  const SizedBox(width: 12),
                  Expanded(child: FieldBox(label: 'Stok *', child: TextFormField(controller: stock, keyboardType: TextInputType.number, style: t(14), validator: intRule))),
                ]),
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
                      final body = <String, Object?>{
                        'name': name.text.trim(),
                        'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
                        'price_idr': int.parse(price.text.trim()),
                        'stock': int.parse(stock.text.trim()),
                      };
                      try {
                        if (tier == null) {
                          await Api.instance.post('/api/admin/events/${event['id']}/tiers', body);
                        } else {
                          await Api.instance.put('/api/admin/tiers/${tier['id']}', body);
                        }
                        if (dc.mounted) Navigator.pop(dc);
                        if (mounted) toast(context, 'Kategori disimpan');
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
      name.dispose();
      desc.dispose();
      price.dispose();
      stock.dispose();
    });
  }

  Future<void> _deleteTier(Map<String, dynamic> tier) async {
    final ok = await confirmDialog(context, title: 'Hapus kategori?', body: 'Kategori "${tier['name']}" akan dihapus.', confirmLabel: 'Hapus', danger: true);
    if (!ok) return;
    try {
      await Api.instance.delete('/api/admin/tiers/${tier['id']}');
      if (mounted) toast(context, 'Kategori dihapus');
      _reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Detail event', style: t(16, w: FontWeight.w700)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: PageBody(
        child: ListView(children: <Widget>[
          FutureBody<Map<String, dynamic>>(future: _f, onRetry: _reload, builder: (c, e) => _body(e)),
        ]),
      ),
    );
  }

  Widget _body(Map<String, dynamic> e) {
    final tiers = (e['tiers'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final status = '${e['status']}';
    Widget kv(String k, String v) => SizedBox(
          width: 240,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(k, style: t(12, color: C.textSoft)),
            const SizedBox(height: 2),
            Text(v.isEmpty ? '-' : v, style: t(14, nums: true)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${e['title']}', style: t(22, w: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(children: <Widget>[StatusBadge(status), const SizedBox(width: 8), Text('${e['artist'] ?? ''}', style: t(13, color: C.textSoft))]),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        FilledButton.icon(onPressed: () => _edit(e), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
        if (status == 'draft') OutlinedButton(onPressed: () => _setStatus(e, 'active'), child: const Text('Publish')),
        if (status == 'active') OutlinedButton(onPressed: () => _setStatus(e, 'draft'), child: const Text('Jadikan draft')),
        if (status != 'cancelled') OutlinedButton(onPressed: () => _setStatus(e, 'cancelled'), child: const Text('Cancel event')),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: C.danger),
          onPressed: () => _delete(e),
          child: const Text('Hapus'),
        ),
      ]),
      const SizedBox(height: 16),
      Panel(
        title: 'Informasi',
        child: Wrap(spacing: 24, runSpacing: 16, children: <Widget>[
          kv('Venue', '${e['venue_name'] ?? ''}'),
          kv('Kategori', '${e['category'] ?? ''}'),
          kv('Mulai', fmtDateTime(e['start_time_utc'])),
          kv('Selesai', fmtDateTime(e['end_time_utc'])),
          kv('Lokasi', e['latitude'] == null ? '' : '${e['latitude']}, ${e['longitude']}'),
          kv('Outdoor', (e['is_outdoor'] == 1 || e['is_outdoor'] == true) ? 'Ya' : 'Tidak'),
          kv('Harga mulai', rp(e['price_idr'])),
          kv('Total stok tersisa', num0(e['stock'])),
          kv('Tiket terjual', num0(e['tickets_sold'])),
          kv('Sudah check-in', num0(e['checked_in'])),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Kategori tiket',
        trailing: TextButton.icon(onPressed: () => _tierDialog(e), icon: const Icon(Icons.add, size: 16), label: const Text('Tambah')),
        padding: const EdgeInsets.all(12),
        child: AdminTable<Map<String, dynamic>>(
          shrink: true,
          empty: 'Belum ada kategori. Harga dan stok event diatur langsung di form edit.',
          rows: tiers,
          cols: <Col<Map<String, dynamic>>>[
            Col('Nama', (r) => cellTwoLine('${r['name']}', '${r['description'] ?? ''}'), width: 200, flex: true),
            Col('Harga', (r) => cellText(rp(r['price_idr']), nums: true), width: 120, right: true),
            Col('Stok', (r) => cellText(num0(r['stock']), nums: true, color: asInt(r['stock']) == 0 ? C.danger : Colors.white), width: 80, right: true),
            Col(
              '',
              (r) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                IconButton(tooltip: 'Ubah', onPressed: () => _tierDialog(e, r), icon: const Icon(Icons.edit_outlined, size: 18, color: C.sky)),
                IconButton(tooltip: 'Hapus', onPressed: () => _deleteTier(r), icon: const Icon(Icons.delete_outline, size: 18, color: C.danger)),
              ]),
              width: 100,
              right: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Tickets',
        padding: const EdgeInsets.all(12),
        child: FutureBody<List<Map<String, dynamic>>>(future: _tf, onRetry: _reload, builder: (c, all) => _tickets(all)),
      ),
    ]);
  }

  Widget _tickets(List<Map<String, dynamic>> all) {
    final used = all.where((x) => x['used_at'] != null).length;
    final q = _ticketQ.toLowerCase();
    final rows = all.where((x) {
      final isUsed = x['used_at'] != null;
      if (_ticketFilter == 'in' && !isUsed) return false;
      if (_ticketFilter == 'out' && isUsed) return false;
      if (q.isEmpty) return true;
      return '${x['ticket_code']} ${x['owner_name']} ${x['owner_email']}'.toLowerCase().contains(q);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
        Text('$used dari ${all.length} sudah check-in', style: t(13, w: FontWeight.w600, nums: true)),
        FilterChips(
          options: const <String, String>{'': 'Semua', 'out': 'Belum masuk', 'in': 'Sudah masuk'},
          value: _ticketFilter,
          onChanged: (v) => setState(() => _ticketFilter = v),
        ),
        SearchField(hint: 'Kode atau nama', onChanged: (v) => setState(() => _ticketQ = v)),
      ]),
      const SizedBox(height: 12),
      AdminTable<Map<String, dynamic>>(
        shrink: true,
        empty: all.isEmpty ? 'Belum ada tiket terjual.' : 'Tidak ada tiket yang cocok.',
        rows: rows,
        cols: <Col<Map<String, dynamic>>>[
          Col('Kode', (r) => cellText('${r['ticket_code']}', mono: true), width: 150),
          Col('Pemilik', (r) => cellTwoLine('${r['owner_name']}', '${r['owner_email']}'), width: 200, flex: true),
          Col('Kategori', (r) => cellText('${r['tier_name'] ?? '-'}'), width: 110),
          Col('Check-in', (r) => r['used_at'] == null ? Text('Belum', style: t(13, color: C.muted)) : cellText(fmtDateTime(r['used_at']), nums: true), width: 150),
          Col('Petugas', (r) => cellText('${r['checked_in_by_name'] ?? '-'}'), width: 120),
        ],
      ),
    ]);
  }
}
