import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/sensor_service.dart';
import '../../services/time_zones.dart';
import '../home/event_times_card.dart';

const Color _kInk = Color(0xFF111827);
const Color _kGrey = Color(0xFF6B7280);

/// E-Ticket: kartu putih dengan sobekan di tengah. Satu pemesanan bisa berisi beberapa tiket
/// (geser QR). Profil artis Spotify ada di halaman detail konser, bukan di sini.
class TicketDetailPage extends StatefulWidget {
  const TicketDetailPage({super.key, required this.group});
  final TicketGroup group;

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  static const List<String> _requirements = <String>[
    'Show this QR code at the gate; one code admits one person.',
    'Bring a valid photo ID that matches the ticket holder.',
    'No professional cameras, drones, or outside food and drinks.',
    'No weapons, sharp objects, or illegal substances.',
    'Arrive at least 60 minutes before the show starts.',
  ];

  final PageController _pager = PageController();
  int _page = 0;
  String? _verifyText;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = widget.group.tickets[_page].code;
    setState(() => _verifyText = 'Checking...');
    try {
      final j = await ApiClient.instance.get('/api/tickets/$code/verify') as Map;
      final ok = j['ticket_registered'] == true && j['chain_valid'] == true;
      if (!mounted) return;
      setState(() => _verifyText = ok
          ? 'Authentic ✔ (block #${j['block_index']})'
          : 'Not valid ✖ ${j['chain_valid'] == false ? '(chain broken at #${j['broken_at']})' : '(not registered)'}');
    } catch (e) {
      if (mounted) setState(() => _verifyText = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final qrSize = landscape ? 170.0 : 210.0;
    final info = _info(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.count > 1 ? 'E-Ticket • ${widget.group.count} tickets' : 'E-Ticket'),
        actions: const <Widget>[RotateButton()],
      ),
      body: SafeArea(
        child: landscape
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Expanded(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[_eTicket(qrSize)])),
                Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), children: info)),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                _eTicket(qrSize),
                const SizedBox(height: 16),
                ...info,
              ]),
      ),
    );
  }

  // ---------------- Kartu e-ticket ----------------
  Widget _eTicket(double qrSize) {
    final g = widget.group;
    final p = zoneParts(g.startUtc, 'Asia/Jakarta');
    final name = Session.instance.user?['name']?.toString() ?? '-';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          // --- bagian atas: detail pemesanan ---
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  const Text('KONFETI',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 12)),
                  const Spacer(),
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 4),
                  const Text('Payment Done',
                      style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                const SizedBox(height: 14),
                Text(g.title, style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800, fontSize: 20, height: 1.2)),
                const SizedBox(height: 2),
                Text(g.artist, style: const TextStyle(color: _kGrey, fontSize: 13)),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFD1D5DB), thickness: 1.2, height: 1),
                const SizedBox(height: 14),
                Row(children: <Widget>[
                  Expanded(child: _kv('Book name', name)),
                  Expanded(child: _kv('Number of person', '${g.count}')),
                ]),
                const SizedBox(height: 12),
                _kv('Venue', g.venueName),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(child: _kv('Date', p.date)),
                  Expanded(child: _kv('Time', '${p.time} ${p.abbr}')),
                ]),
                const SizedBox(height: 12),
                _kv('Order', g.orderId),
                const SizedBox(height: 14),
              ]),
            ),
          ),
          // --- sobekan: setengah lingkaran kiri & kanan + garis putus ---
          ClipPath(
            clipper: const _TearClipper(14),
            child: Container(
              height: 28,
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              child: LayoutBuilder(
                builder: (_, c) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List<Widget>.generate(
                    math.max(1, (c.maxWidth / 10).floor()),
                    (_) => Container(width: 5, height: 1.5, color: const Color(0xFFCBD5E1)),
                  ),
                ),
              ),
            ),
          ),
          // --- bagian bawah: QR + barcode ---
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
              child: _qrPager(qrSize),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _kv(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label, style: const TextStyle(color: _kGrey, fontSize: 11)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(color: _kInk, fontWeight: FontWeight.w700, fontSize: 14)),
      ]);

  /// QR per tiket dalam satu order: geser kiri/kanan.
  Widget _qrPager(double qrSize) {
    final g = widget.group;
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      SizedBox(
        height: qrSize + 112,
        child: PageView.builder(
          controller: _pager,
          itemCount: g.count,
          onPageChanged: (i) => setState(() {
            _page = i;
            _verifyText = null;
          }),
          itemBuilder: (_, i) {
            final t = g.tickets[i];
            return Column(children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                ),
                child: QrImageView(data: t.code, size: qrSize, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 10),
              SizedBox(width: qrSize + 16, height: 44, child: CustomPaint(painter: _BarcodePainter(t.code))),
              const SizedBox(height: 6),
              SelectableText(t.code, style: const TextStyle(color: _kInk, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            ]);
          },
        ),
      ),
      if (g.count > 1) ...<Widget>[
        Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          for (var i = 0; i < g.count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _page ? AppColors.primary : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text('Ticket ${_page + 1} of ${g.count} • swipe for the next one',
            style: const TextStyle(color: _kGrey, fontSize: 12)),
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _verify,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
        icon: const Icon(Icons.verified_outlined, size: 18),
        label: Text(_verifyText ?? 'Verify authenticity'),
      ),
    ]);
  }

  // ---------------- Info di bawah tiket ----------------
  List<Widget> _info(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.group;
    return <Widget>[
      EventTimesCard(startUtc: g.startUtc),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Entry requirements', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final r in _requirements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const Icon(Icons.check, size: 16, color: AppColors.sun),
                const SizedBox(width: 8),
                Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        color: theme.colorScheme.errorContainer,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.sos, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Text('Emergency', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          const Text('In an emergency, shake your phone hard 3 times within 2 seconds, on any screen of the app. '
              'A 5-second countdown starts; you can cancel before the alert is sent to event staff.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: SensorService.instance.startEmergency,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Send alert manually'),
          ),
          const SizedBox(height: 8),
          Text('Tip: twist your phone quickly like a steering wheel to rotate the screen, on any page.',
              style: theme.textTheme.bodySmall),
        ]),
      ),
    ];
  }
}

/// Memotong setengah lingkaran di sisi kiri & kanan (efek sobekan tiket).
class _TearClipper extends CustomClipper<Path> {
  const _TearClipper(this.radius);
  final double radius;

  @override
  Path getClip(Size size) {
    final rect = Path()..addRect(Offset.zero & size);
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, size.height / 2), radius: radius))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height / 2), radius: radius));
    return Path.combine(PathOperation.difference, rect, holes);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Barcode dekoratif dari kode tiket (yang dipindai tetap QR).
class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _kInk;
    final units = data.codeUnits;
    var x = 0.0;
    var i = 0;
    var bar = true;
    while (x < size.width) {
      final u = units[i % units.length] + i * 7;
      final w = 1.0 + (u % 3) * 1.2;
      if (bar) canvas.drawRect(Rect.fromLTWH(x, 0, math.min(w, size.width - x), size.height), paint);
      x += w;
      bar = !bar;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) => oldDelegate.data != data;
}
