import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/checkout_draft.dart';
import '../../services/time_zones.dart';
import '../shell/shell_nav.dart';

/// Payment: jumlah tiket, kode promo, konversi mata uang (IDR/USD/EUR/JPY/SGD/MYR), lalu bayar.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.event, this.tier});
  final Event event;

  /// Kategori tiket yang dipilih di halaman detail (null = event tanpa kategori).
  final TicketTier? tier;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final TextEditingController _promo = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nik = TextEditingController();
  late final TextEditingController _fullName =
      TextEditingController(text: Session.instance.user?['name']?.toString() ?? '');
  final TextEditingController _age = TextEditingController();
  String? _gender; // 'Male' | 'Female'
  CheckoutDraft? _draft; // data diri dari pembelian sebelumnya (jika ada)
  bool _draftHandled = false; // true setelah user memilih "use saved" / "type again"
  int _qty = 1;
  int _discountPercent = 0;
  String? _appliedCode;
  String? _promoError;

  Map<String, double> _rates = <String, double>{'IDR': 1};
  String _rateSource = '';
  String _currency = 'IDR';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRates();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final d = await CheckoutDraft.load();
    if (mounted && d != null) setState(() => _draft = d);
  }

  void _useDraft() {
    final d = _draft!;
    setState(() {
      _fullName.text = d.name;
      _nik.text = d.nik;
      _age.text = d.age;
      _gender = (d.gender == 'Male' || d.gender == 'Female') ? d.gender : null;
      _draftHandled = true;
    });
  }

  void _typeAgain() {
    setState(() {
      _fullName.clear();
      _nik.clear();
      _age.clear();
      _gender = null;
      _draftHandled = true;
    });
  }

  Future<void> _forgetDraft() async {
    await CheckoutDraft.clear();
    if (mounted) setState(() => _draft = null);
  }

  @override
  void dispose() {
    _promo.dispose();
    _nik.dispose();
    _fullName.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _loadRates() async {
    try {
      final j = await ApiClient.instance.get('/api/rates') as Map;
      final r = (j['rates'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      if (mounted) {
        setState(() {
          _rates = r;
          _rateSource = (j['source'] ?? '').toString();
        });
      }
    } catch (_) {/* tetap tampilkan IDR saja */}
  }

  // Rumus sama dengan backend: harga satuan dibulatkan dulu, baru dikali qty.
  int get _basePrice => widget.tier?.priceIdr ?? widget.event.priceIdr;
  int get _unit => ((_basePrice * (100 - _discountPercent)) / 100).round();
  int get _total => _unit * _qty;
  int get _maxQty => (widget.tier?.stock ?? widget.event.stock).clamp(1, AppConfig.maxQtyPerOrder);

  Future<void> _applyPromo() async {
    final code = _promo.text.trim().toUpperCase();
    if (code.isEmpty) return;
    try {
      final j = await ApiClient.instance.get('/api/promos/validate', query: <String, String>{'code': code}) as Map;
      setState(() {
        _discountPercent = (j['discount_percent'] as num).toInt();
        _appliedCode = j['code'] as String;
        _promoError = null;
      });
    } on ApiException catch (e) {
      setState(() {
        _discountPercent = 0;
        _appliedCode = null;
        _promoError = e.status == 404 ? 'Invalid promo code' : e.message;
      });
    }
  }

  Future<void> _pay() async {
    // Data diri wajib valid sebelum transaksi dibuat.
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete your personal data.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.post('/api/orders', <String, Object?>{
        'event_id': widget.event.id,
        'qty': _qty,
        if (widget.tier != null) 'tier_id': widget.tier!.id,
        'buyer': <String, Object?>{
          'nik': _nik.text.trim(),
          'name': _fullName.text.trim(),
          'age': int.parse(_age.text.trim()),
          'gender': _gender,
        },
        if (_appliedCode != null) 'promo_code': _appliedCode,
      }) as Map;
      final orderId = res['order_id'] as String;
      // Order berhasil dibuat: simpan data diri untuk pembelian berikutnya.
      await CheckoutDraft.save(
        name: _fullName.text.trim(),
        nik: _nik.text.trim(),
        age: _age.text.trim(),
        gender: _gender ?? '',
      );
      if (!mounted) return;

      if (res['demo'] == true) {
        final pay = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Demo payment'),
            content: const Text('Midtrans is not configured on the server. Simulate a successful payment?'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Pay later')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simulate payment')),
            ],
          ),
        );
        if (pay == true) await ApiClient.instance.post('/api/orders/dev/simulate-paid/$orderId');
      } else {
        final url = res['redirect_url'] as String?;
        if (url != null) {
          final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          if (!ok && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Could not open the payment page.')));
          }
        }
      }
      if (!mounted) return;
      Navigator.popUntil(context, (r) => r.isFirst);
      ShellNav.goToPending(); // status order akan diperbarui otomatis di My Tickets
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final rate = _rates[_currency] ?? 1;
    final p = zoneParts(e.startUtc, 'Asia/Jakarta');
    return Scaffold(
      appBar: AppBar(title: const Text('Payment'), actions: const <Widget>[RotateButton()]),
      body: AppBackground(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: <Widget>[
          GlassCard(
            highlight: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(e.title, style: AppText.display(size: 22, height: 1.15)),
              const SizedBox(height: 4),
              Text('${e.artistLabel} • ${e.venueName}', style: const TextStyle(color: AppColors.sky, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                const Icon(Icons.event, size: 16, color: AppColors.sun),
                const SizedBox(width: 6),
                Text('${p.date} • ${p.time} ${p.abbr}', style: const TextStyle(fontSize: 13)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Row(children: <Widget>[
              const Expanded(child: Text('Tickets', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              IconButton.filledTonal(
                tooltip: 'Fewer tickets',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.glassHigh,
                  foregroundColor: AppColors.sun,
                  disabledBackgroundColor: AppColors.glass,
                  disabledForegroundColor: AppColors.skyDim,
                ),
                onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 48,
                child: Text('$_qty',
                    textAlign: TextAlign.center, style: AppText.display(size: 26, weight: FontWeight.w700)),
              ),
              IconButton.filledTonal(
                tooltip: 'More tickets',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.glassHigh,
                  foregroundColor: AppColors.sun,
                  disabledBackgroundColor: AppColors.glass,
                  disabledForegroundColor: AppColors.skyDim,
                ),
                onPressed: _qty < _maxQty ? () => setState(() => _qty++) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
          const SectionHeader('Personal data', padding: EdgeInsets.fromLTRB(0, 20, 0, 10)),
          if (_draft != null && !_draftHandled) ...<Widget>[
            GlassCard(
              highlight: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const Text('Use your saved data?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '${_draft!.name} • NIK ${_draft!.maskedNik}\n${_draft!.age} years • ${_draft!.gender}',
                  style: const TextStyle(color: AppColors.sky, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(child: FilledButton(onPressed: _useDraft, child: const Text('Use saved data'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: _typeAgain, child: const Text('Type again'))),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _forgetDraft, child: const Text('Delete saved data')),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          GlassCard(
            blur: true,
            child: Form(
              key: _formKey,
              child: Column(children: <Widget>[
                TextFormField(
                  controller: _nik,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
                  decoration: const InputDecoration(labelText: 'NIK (16 digits)', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => RegExp(r'^\d{16}$').hasMatch((v ?? '').trim()) ? null : 'NIK must be 16 digits',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fullName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name (as on ID)', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v ?? '').trim().length < 3 ? 'Please enter your full name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return (n == null || n < 5 || n > 100) ? 'Enter a valid age' : null;
                  },
                ),
                const SizedBox(height: 12),
                FormField<String>(
                  validator: (_) => _gender == null ? 'Please choose a gender' : null,
                  builder: (state) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    const Text('Gender', style: TextStyle(color: AppColors.sky, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(children: <Widget>[
                      for (final g in const <String>['Male', 'Female']) ...<Widget>[
                        CategoryPill(
                          label: g,
                          icon: g == 'Male' ? Icons.male_rounded : Icons.female_rounded,
                          selected: _gender == g,
                          onTap: () {
                            setState(() => _gender = g);
                            state.didChange(g);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ]),
                    if (state.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(state.errorText!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(
              child: TextField(
                controller: _promo,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Promo code',
                  prefixIcon: const Icon(Icons.local_offer_outlined),
                  errorText: _promoError,
                  helperText: _appliedCode != null ? '$_appliedCode applied: $_discountPercent% off' : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton(
                onPressed: _applyPromo,
                style: FilledButton.styleFrom(minimumSize: const Size(64, 48), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                child: const Text('Apply'),
              ),
            ),
          ]),
          const SectionHeader('Show price in', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (final code in _rates.keys)
              CategoryPill(label: code, selected: _currency == code, onTap: () => setState(() => _currency = code)),
          ]),
          const SizedBox(height: 20),
          AppCard(
            child: Column(children: <Widget>[
              if (widget.tier != null) _row('Category', widget.tier!.name),
              _row('Price per ticket', rupiah(_basePrice)),
              if (_discountPercent > 0) _row('Discount', '-$_discountPercent%', valueColor: AppColors.butter),
              _row('Quantity', '× $_qty'),
              const Divider(height: 24),
              _row('Total (charged in IDR)', rupiah(_total), bold: true, big: true),
              if (_currency != 'IDR') _row('≈ Total in $_currency', money(_total * rate, _currency), bold: true, valueColor: AppColors.sun),
            ]),
          ),
          if (_currency != 'IDR')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Converted amount is an estimate${_rateSource == 'fallback' ? ' (offline rates)' : ''}. '
                'You will pay in IDR.',
                style: const TextStyle(color: AppColors.sky, fontSize: 12),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.glassHigh,
              border: Border(top: BorderSide(color: AppColors.glassBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _busy ? null : _pay,
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                        : Text('Pay ${rupiah(_total)}'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, bool big = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: bold ? Colors.white : AppColors.sky)),
        Text(value,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: big ? 18 : 14, color: valueColor ?? Colors.white)),
      ]),
    );
  }
}