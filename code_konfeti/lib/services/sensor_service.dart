import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/api_client.dart';
import '../core/navigation.dart';
import '../models/event.dart';
import 'alert_sound.dart';
import 'emergency_dialog.dart';
import 'shake_detector.dart';

/// Sensor yang aktif di SEMUA halaman:
///  - Gyroscope (sejak aplikasi dibuka, termasuk halaman login): memutar HP cepat seperti setir
///    (sumbu Z) -> ganti orientasi vertikal/horizontal. Tombol [RotateButton] sebagai cadangan.
///  - Accelerometer (selama login): 3 guncangan kuat dalam 2 detik -> hitung mundur 5 detik -> alert darurat.
class SensorService {
  SensorService._();
  static final SensorService instance = SensorService._();

  /// Kecepatan putar (rad/s) pada sumbu Z yang dianggap "twist". Turunkan jika kurang peka.
  static const double twistThreshold = 3.0;

  ShakeDetector? _shake;
  StreamSubscription<GyroscopeEvent>? _gyro;
  bool _landscape = false;
  bool _emergencyBusy = false;
  DateTime _lastFlip = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------- Gyroscope ----------
  void startGyroscope() {
    if (_gyro != null) return;
    _gyro = gyroscopeEventStream().listen((e) {
      final now = DateTime.now();
      if (e.z.abs() > twistThreshold && now.difference(_lastFlip) > const Duration(milliseconds: 1200)) {
        _lastFlip = now;
        HapticFeedback.selectionClick();
        toggleOrientation();
      }
    }, onError: (Object _) {/* tanpa gyroscope: pakai tombol rotasi */});
  }

  void toggleOrientation() {
    _landscape = !_landscape;
    SystemChrome.setPreferredOrientations(_landscape
        ? <DeviceOrientation>[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : <DeviceOrientation>[DeviceOrientation.portraitUp]);
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1200),
        content: Text(_landscape ? 'Landscape mode' : 'Portrait mode'),
      ));
  }

  // ---------- Accelerometer: darurat ----------
  void setEmergencyEnabled(bool enabled) {
    if (enabled) {
      _shake ??= ShakeDetector(onShake: startEmergency)..start();
    } else {
      _shake?.stop();
      _shake = null;
    }
  }

  Future<void> startEmergency() async {
    // overlay.context berada di bawah Navigator, jadi aman untuk showDialog dari mana saja
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (_emergencyBusy || ctx == null) return;
    _emergencyBusy = true;
    try {
      final send = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => const EmergencyCountdownDialog(seconds: 5),
      );
      if (send == true) await _sendEmergency();
    } finally {
      _emergencyBusy = false;
    }
  }

  /// Pilih tiket aktif yang sedang berlangsung (atau tiket aktif pertama) agar staf tahu event-nya.
  Future<Ticket?> _pickTicket() async {
    try {
      final list = await ApiClient.instance.get('/api/tickets') as List;
      final active = list
          .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((t) => t.state == 'active')
          .toList();
      if (active.isEmpty) return null;
      return active.firstWhere((t) => t.isLive, orElse: () => active.first);
    } catch (_) {
      return null;
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
      return null; // GPS mati / timeout: alert tetap dikirim tanpa koordinat
    }
  }

  Future<void> _sendEmergency() async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[_pickTicket(), _tryPosition()]);
    final ticket = results[0] as Ticket?;
    final pos = results[1] as Position?;
    try {
      await ApiClient.instance.post('/api/emergency', <String, Object?>{
        if (ticket != null) 'event_id': ticket.eventId,
        if (ticket != null) 'ticket_code': ticket.code,
        if (pos != null) 'latitude': pos.latitude,
        if (pos != null) 'longitude': pos.longitude,
      });
      AlertSound.instance.playConfirm();
      _toast('Emergency alert sent. Stay where you are, staff are notified.');
    } catch (e) {
      _toast('Failed to send alert: $e');
    }
  }

  void _toast(String m) => messengerKey.currentState?.showSnackBar(SnackBar(content: Text(m)));
}
