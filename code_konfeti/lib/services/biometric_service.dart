import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// True bila perangkat punya sidik jari/wajah (atau PIN/pola) yang sudah terdaftar.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Metode yang bisa dipilih pengguna: 'fingerprint' dan/atau 'face'.
  /// Bila perangkat hanya melaporkan "strong/weak" tanpa merinci jenisnya, keduanya ditawarkan.
  Future<List<String>> availableMethods() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      final out = <String>[];
      if (types.contains(BiometricType.fingerprint)) out.add('fingerprint');
      if (types.contains(BiometricType.face)) out.add('face');
      if (out.isEmpty && (types.contains(BiometricType.strong) || types.contains(BiometricType.weak))) {
        out.addAll(<String>['fingerprint', 'face']);
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    }
  }
}
