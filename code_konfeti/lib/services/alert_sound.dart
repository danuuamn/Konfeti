import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Suara alert darurat, dibangkitkan lewat kode (WAV 16-bit mono) sehingga tanpa file audio/asset.
///  - [startSiren]   : sirene naik-turun, berulang selama hitung mundur.
///  - [playConfirm]  : dua nada pendek saat alert berhasil terkirim.
class AlertSound {
  AlertSound._();
  static final AlertSound instance = AlertSound._();

  static const int _rate = 22050;
  final AudioPlayer _player = AudioPlayer();
  Uint8List? _siren;
  Uint8List? _chime;

  Future<void> startSiren() async {
    try {
      _siren ??= _buildSiren();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(BytesSource(_siren!));
    } catch (_) {/* tanpa suara pun alert tetap berjalan */}
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> playConfirm() async {
    try {
      _chime ??= _buildChime();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(1.0);
      await _player.play(BytesSource(_chime!));
    } catch (_) {}
  }

  // ---------- pembangkit suara ----------

  /// Sirene: frekuensi bergerak 700 -> 1400 Hz -> 700 Hz setiap 1 detik. Durasi 2 detik, di-loop.
  Uint8List _buildSiren() {
    final n = _rate * 2;
    final samples = List<double>.filled(n, 0);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = (i / _rate) % 1.0;
      final tri = t < 0.5 ? t * 2 : 2 - t * 2; // 0..1..0
      final f = 700 + 700 * tri;
      phase += 2 * math.pi * f / _rate;
      samples[i] = 0.85 * (math.sin(phase) + 0.25 * math.sin(3 * phase)) / 1.25;
    }
    return _wav(samples);
  }

  /// Konfirmasi: nada 880 Hz lalu 1320 Hz dengan fade-out.
  Uint8List _buildChime() {
    final samples = <double>[];
    void tone(double freq, double seconds) {
      final n = (_rate * seconds).round();
      for (var i = 0; i < n; i++) {
        final env = 1 - i / n; // fade-out
        samples.add(0.7 * env * math.sin(2 * math.pi * freq * i / _rate));
      }
    }

    tone(880, 0.15);
    tone(1320, 0.30);
    return _wav(samples);
  }

  Uint8List _wav(List<double> samples) {
    final data = ByteData(44 + samples.length * 2);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      data.setInt16(44 + i * 2, v, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
