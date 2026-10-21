import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class _TierDraft {
  final name = TextEditingController();
  final desc = TextEditingController();
  final price = TextEditingController();
  final stock = TextEditingController();
  void dispose() {
    name.dispose();
    desc.dispose();
    price.dispose();
    stock.dispose();
  }
}

/// Form buat / ubah event. Saat membuat, kategori tiket bisa diisi sekaligus.
/// Saat mengubah event yang sudah punya kategori, harga & stok diatur dari kategori (di halaman detail).
class EventFormPage extends StatefulWidget {
  const EventFormPage({super.key, this.event});
  final Map<String, dynamic>? event;
  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final _form = GlobalKey<FormState>();
  late final bool _edit = widget.event != null;
  late final bool _hasTiers = _edit && (widget.event!['tiers'] as List? ?? const <Object?>[]).isNotEmpty;

  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _category = TextEditingController();
  final _venue = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _image = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  bool _outdoor = false;
  String _status = 'active';
  DateTime? _start;
  DateTime? _end;
  final List<_TierDraft> _tiers = <_TierDraft>[];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e != null) {
      _title.text = '${e['title'] ?? ''}';
      _artist.text = '${e['artist'] ?? ''}';
      _category.text = '${e['category'] ?? ''}';
      _venue.text = '${e['venue_name'] ?? ''}';
      _lat.text = e['latitude'] == null ? '' : '${e['latitude']}';
      _lng.text = e['longitude'] == null ? '' : '${e['longitude']}';
      _image.text = '${e['image_url'] ?? ''}';
      _price.text = '${e['price_idr'] ?? ''}';
      _stock.text = '${e['stock'] ?? ''}';
      _outdoor = e['is_outdoor'] == 1 || e['is_outdoor'] == true;
      _status = '${e['status'] ?? 'active'}';
      _start = parseUtc(e['start_time_utc']);
      _end = parseUtc(e['end_time_utc']);
    } else {
      _tiers.add(_TierDraft());
    }
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[_title, _artist, _category, _venue, _lat, _lng, _image, _price, _stock]) {
      c.dispose();
    }
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final base = initial ?? DateTime.now().add(const Duration(days: 7));
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return null;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null) return null;
    return DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;
  String? _intRule(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < 0 ? 'Angka >= 0' : null;
  }

  String? _coord(String? v, double limit) {
    if (v == null || v.trim().isEmpty) return null;
    final d = double.tryParse(v.trim().replaceAll(',', '.'));
    return d == null || d < -limit || d > limit ? 'Harus -$limit..$limit' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_start == null || _end == null) {
      setState(() => _error = 'Waktu mulai dan selesai wajib diisi.');
      return;
    }
    if (!_end!.isAfter(_start!)) {
      setState(() => _error = 'Waktu selesai harus setelah waktu mulai.');
      return;
    }
    String? nul(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    double? dbl(TextEditingController c) => c.text.trim().isEmpty ? null : double.parse(c.text.trim().replaceAll(',', '.'));

    final body = <String, Object?>{
      'title': _title.text.trim(),
      'artist': nul(_artist),
      'category': nul(_category),
      'venue_name': nul(_venue),
      'latitude': dbl(_lat),
      'longitude': dbl(_lng),
      'is_outdoor': _outdoor ? 1 : 0,
      'image_url': nul(_image),
      'start_time_utc': _start!.toUtc().toIso8601String(),
      'end_time_utc': _end!.toUtc().toIso8601String(),
      'status': _status,
    };
    if (!_edit) {
      final tiers = _tiers.where((t) => t.name.text.trim().isNotEmpty || t.price.text.trim().isNotEmpty).toList();
      if (tiers.isNotEmpty) {
        for (final t in tiers) {
          if (t.name.text.trim().isEmpty || int.tryParse(t.price.text.trim()) == null || int.tryParse(t.stock.text.trim()) == null) {
            setState(() => _error = 'Setiap kategori tiket butuh nama, harga, dan stok (angka).');
            return;
          }
        }
        body['tiers'] = tiers
            .map((t) => <String, Object?>{
                  'name': t.name.text.trim(),
                  'description': t.desc.text.trim().isEmpty ? null : t.desc.text.trim(),
                  'price_idr': int.parse(t.price.text.trim()),
                  'stock': int.parse(t.stock.text.trim()),
                })
            .toList();
      } else {
        body['price_idr'] = int.parse(_price.text.trim());
        body['stock'] = int.parse(_stock.text.trim());
      }
    } else if (!_hasTiers) {
      body['price_idr'] = int.parse(_price.text.trim());
      body['stock'] = int.parse(_stock.text.trim());
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = _edit
          ? await Api.instance.put('/api/admin/events/${widget.event!['id']}', body)
          : await Api.instance.post('/api/admin/events', body);
      if (!mounted) return;
      toast(context, _edit ? 'Event diperbarui' : 'Event dibuat');
      Navigator.pop(context, asInt((res as Map)['id']));
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dateField(String label, DateTime? v, ValueChanged<DateTime> set) {
    return FieldBox(
      label: label,
      width: 240,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final d = await _pick(v);
          if (d != null) setState(() => set(d));
        },
        child: InputDecorator(
          decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: C.sky)),
          child: Text(v == null ? 'Pilih' : fmtDateTime(v.toUtc().toIso8601String()), style: t(14, color: v == null ? C.muted : Colors.white)),
        ),
      ),
    );
  }

  bool _imgBusy = false;

  /// Ambil foto artis dari Spotify (lewat backend) berdasarkan isi kolom Artis.
  Future<void> _fetchImage() async {
    final name = _artist.text.trim();
    if (name.isEmpty) {
      toast(context, 'Isi nama artis dulu.', error: true);
      return;
    }
    setState(() => _imgBusy = true);
    try {
      final r = await Api.instance.get('/api/admin/spotify/artist-image', query: <String, String?>{'name': name}) as Map;
      final url = (r['image'] ?? '').toString();
      if (url.isNotEmpty && mounted) {
        setState(() => _image.text = url);
        toast(context, 'Gambar diisi dari Spotify.');
      }
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _imgBusy = false);
    }
  }

  Widget _imageField() {
    final url = _image.text.trim();
    return FieldBox(
      label: 'URL gambar',
      width: 508,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(
            child: TextFormField(
              controller: _image,
              style: t(14),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(counterText: '', hintText: 'https://... atau tekan "Ambil dari Spotify"'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _imgBusy ? null : _fetchImage,
            icon: _imgBusy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.music_note, size: 16),
            label: const Text('Ambil dari Spotify'),
          ),
        ]),
        if (url.startsWith('http')) ...<Widget>[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 120,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 120,
                height: 120,
                color: C.panel,
                alignment: Alignment.center,
                child: Text('Gambar tidak bisa dimuat', textAlign: TextAlign.center, style: t(11, color: C.muted)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _tf(String label, TextEditingController c, {double width = 240, String? Function(String?)? validator, TextInputType? type, int? max}) {
    return FieldBox(
      label: label,
      width: width,
      child: TextFormField(controller: c, validator: validator, keyboardType: type, maxLength: max, style: t(14), decoration: const InputDecoration(counterText: '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_edit ? 'Edit event' : 'New event', style: t(16, w: FontWeight.w700)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Panel(
                  title: 'Informasi',
                  child: Wrap(spacing: 16, runSpacing: 16, children: <Widget>[
                    _tf('Judul *', _title, width: 508, validator: (v) => _req(v) ?? (v!.trim().length > 120 ? 'Maks. 120 karakter' : null), max: 120),
                    _tf('Artis', _artist),
                    _tf('Kategori (mis. Pop, Rock)', _category),
                    _tf('Venue', _venue, width: 508),
                    _tf('Latitude', _lat, validator: (v) => _coord(v, 90), type: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                    _tf('Longitude', _lng, validator: (v) => _coord(v, 180), type: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                    _imageField(),
                    _dateField('Mulai *', _start, (d) => _start = d),
                    _dateField('Selesai *', _end, (d) => _end = d),
                    FieldBox(
                      label: 'Status',
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        dropdownColor: C.panel,
                        style: t(14),
                        items: const <String>['active', 'draft', 'cancelled'].map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setState(() => _status = v ?? _status),
                      ),
                    ),
                    FieldBox(
                      label: 'Outdoor',
                      width: 240,
                      child: Align(alignment: Alignment.centerLeft, child: Switch(value: _outdoor, onChanged: (v) => setState(() => _outdoor = v))),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                if (_hasTiers)
                  Panel(child: Text('Harga dan stok event ini dihitung dari kategori tiket. Ubah kategori di halaman detail event.', style: t(13, color: C.textSoft)))
                else if (_edit)
                  Panel(
                    title: 'Harga & stok',
                    child: Wrap(spacing: 16, children: <Widget>[
                      _tf('Harga (IDR) *', _price, validator: _intRule, type: TextInputType.number),
                      _tf('Stok *', _stock, validator: _intRule, type: TextInputType.number),
                    ]),
                  )
                else
                  Panel(
                    title: 'Kategori tiket',
                    trailing: TextButton.icon(
                      onPressed: () => setState(() => _tiers.add(_TierDraft())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Tambah kategori'),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('Isi minimal satu kategori. Harga mulai dan total stok event dihitung otomatis.', style: t(12, color: C.textSoft)),
                      const SizedBox(height: 12),
                      for (var i = 0; i < _tiers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: <Widget>[
                            _tf('Nama', _tiers[i].name, width: 150, max: 40),
                            _tf('Deskripsi', _tiers[i].desc, width: 220, max: 200),
                            _tf('Harga (IDR)', _tiers[i].price, width: 130, type: TextInputType.number),
                            _tf('Stok', _tiers[i].stock, width: 90, type: TextInputType.number),
                            if (_tiers.length > 1)
                              IconButton(
                                tooltip: 'Hapus kategori',
                                onPressed: () => setState(() => _tiers.removeAt(i).dispose()),
                                icon: const Icon(Icons.close, size: 18, color: C.danger),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(_error!, style: t(13, color: C.danger)),
                ],
                const SizedBox(height: 20),
                Row(children: <Widget>[
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink)) : Text(_edit ? 'Simpan perubahan' : 'Buat event'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
