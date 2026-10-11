import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/api_client.dart';
import '../../models/event.dart';
import '../home/event_times_card.dart';
import 'emergency_dialog.dart';
import 'shake_detector.dart';

/// Detail tiket: QR, syarat masuk, waktu event, darurat (shake) dan rotasi layar (gyroscope).
class TicketDetailPage extends StatefulWidget {
  const TicketDetailPage({super.key, required this.ticket});
  final Ticket ticket;

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

  ShakeDetector? _shake;
  StreamSubscription<GyroscopeEvent>? _gyro;
  bool _landscape = false;
  DateTime _lastFlip = DateTime.fromMillisecondsSinceEpoch(0);
  bool _emergencyBusy = false;
  String? _verifyText;

  @override
  void initState() {
    super.initState();
    _applyOrientation();
    _shake = ShakeDetector(onShake: _startEmergency)..start();
    // Sensor 2: Gyroscope. Memutar HP seperti setir (sumbu Z) dengan cepat = ganti orientasi layar.
    _gyro = gyroscopeEventStream().listen((e) {
      final now = DateTime.now();
      if (e.z.abs() > 4.0 && now.difference(_lastFlip) > const Duration(milliseconds: 1200)) {
        _lastFlip = now;
        _toggleOrientation();
      }
    }, onError: (Object _) {/* perangkat tanpa gyroscope: tombol manual tetap ada */});
  }

  @override
  void dispose() {
    _shake?.stop();
    _gyro?.cancel();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _applyOrientation() {
    SystemChrome.setPreferredOrientations(_landscape
        ? <DeviceOrientation>[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : <DeviceOrientation>[DeviceOrientation.portraitUp]);
  }

  void _toggleOrientation() {
    if (!mounted) return;
    setState(() => _landscape = !_landscape);
    _applyOrientation();
  }

  // ---------- Darurat ----------
  Future<void> _startEmergency() async {
    if (_emergencyBusy || !mounted) return;
    _emergencyBusy = true;
    try {
      final send = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const EmergencyCountdownDialog(seconds: 5),
      );
      if (send == true) await _sendEmergency();
    } finally {
      _emergencyBusy = false;
    }
  }

  Future<Position?> _tryPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 6)),
      );
    } catch (_) {
      return null; // GPS mati / timeout: tetap kirim alert tanpa koordinat
    }
  }

  Future<void> _sendEmergency() async {
    final t = widget.ticket;
    final pos = await _tryPosition();
    try {
      await ApiClient.instance.post('/api/emergency', <String, Object?>{
        'event_id': t.eventId,
        'ticket_code': t.code,
        if (pos != null) 'latitude': pos.latitude,
        if (pos != null) 'longitude': pos.longitude,
      });
      _toast('Emergency alert sent. Stay where you are, staff are notified.');
    } catch (e) {
      _toast('Failed to send alert: $e');
    }
  }

  // ---------- Verifikasi blockchain (endpoint milik Ilham) ----------
  Future<void> _verify() async {
    setState(() => _verifyText = 'Checking...');
    try {
      final j = await ApiClient.instance.get('/api/tickets/${widget.ticket.code}/verify') as Map;
      final ok = j['ticket_registered'] == true && j['chain_valid'] == true;
      setState(() => _verifyText = ok
          ? 'Authentic ✔ (block #${j['block_index']})'
          : 'Not valid ✖ ${j['chain_valid'] == false ? '(chain broken at #${j['broken_at']})' : '(not registered)'}');
    } catch (e) {
      setState(() => _verifyText = e.toString());
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final qr = Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: QrImageView(data: t.code, size: landscape ? 220 : 240),
      ),
    );
    final info = _info(context, t);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rotate screen',
            icon: const Icon(Icons.screen_rotation),
            onPressed: _toggleOrientation,
          ),
        ],
      ),
      body: SafeArea(
        child: landscape
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Expanded(child: Center(child: qr)),
                Expanded(child: ListView(padding: const EdgeInsets.all(16), children: info)),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: <Widget>[qr, const SizedBox(height: 16), ...info]),
      ),
    );
  }

  List<Widget> _info(BuildContext context, Ticket t) {
    final theme = Theme.of(context);
    return <Widget>[
      Text(t.title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
      Text('${t.artist} • ${t.venueName}', textAlign: TextAlign.center),
      const SizedBox(height: 4),
      SelectableText(t.code,
          textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
      const SizedBox(height: 8),
      Center(
        child: OutlinedButton.icon(
          onPressed: _verify,
          icon: const Icon(Icons.verified_outlined),
          label: Text(_verifyText ?? 'Verify authenticity'),
        ),
      ),
      const SizedBox(height: 12),
      EventTimesCard(startUtc: t.startUtc),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Entry requirements', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final r in _requirements)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  const Text('•  '),
                  Expanded(child: Text(r)),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Icon(Icons.sos, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Text('Emergency', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            const Text('In an emergency, shake your phone hard 3 times within 2 seconds. '
                'A 5-second countdown starts; you can cancel before the alert is sent to event staff.'),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _startEmergency,
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Send alert manually'),
            ),
            const SizedBox(height: 4),
            Text('Tip: twist your phone quickly like a steering wheel to rotate the screen.',
                style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    ];
  }
}
