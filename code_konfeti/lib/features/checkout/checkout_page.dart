import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/time_zones.dart';
import '../shell/shell_nav.dart';

/// Payment: jumlah tiket, kode promo, konversi mata uang (IDR/USD/EUR/JPY/SGD/MYR), lalu bayar.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.event});
  final Event event;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final TextEditingController _promo = TextEditingController();
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
  }

  @override
  void dispose() {
    _promo.dispose();
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
  int get _unit => ((widget.event.priceIdr * (100 - _discountPercent)) / 100).round();
  int get _total => _unit * _qty;
  int get _maxQty => widget.event.stock.clamp(1, AppConfig.maxQtyPerOrder);

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
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.post('/api/orders', <String, Object?>{
        'event_id': widget.event.id,
        'qty': _qty,
        if (_appliedCode != null) 'promo_code': _appliedCode,
      }) as Map;
      final orderId = res['order_id'] as String;
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
    final theme = Theme.of(context);
    final e = widget.event;
    final rate = _rates[_currency] ?? 1;
    final p = zoneParts(e.startUtc, 'Asia/Jakarta');
    return Scaffold(
      appBar: AppBar(title: const Text('Payment'), actions: const <Widget>[RotateButton()]),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(e.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${e.artistLabel} • ${e.venueName}', style: const TextStyle(color: AppColors.sky, fontSize: 13)),
            const SizedBox(height: 8),
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
            const Expanded(child: Text('Tickets', style: TextStyle(fontWeight: FontWeight.w600))),
            IconButton.filledTonal(
                onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$_qty', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            IconButton.filledTonal(
                onPressed: _qty < _maxQty ? () => setState(() => _qty++) : null, icon: const Icon(Icons.add)),
          ]),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(
            child: TextField(
              controller: _promo,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Promo code',
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
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
              child: const Text('Apply'),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Text('Show price in', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final code in _rates.keys)
            CategoryPill(label: code, selected: _currency == code, onTap: () => setState(() => _currency = code)),
        ]),
        const SizedBox(height: 20),
        AppCard(
          child: Column(children: <Widget>[
            _row('Price per ticket', rupiah(e.priceIdr)),
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: AppColors.bgAlt, border: Border(top: BorderSide(color: AppColors.skyFaint))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _pay,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                    : Text('Pay ${rupiah(_total)}'),
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
