import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'navigation.dart';
import 'session.dart';

/// Membungkus seluruh app (dipasang di MaterialApp.builder). Bila pengguna login dan tidak
/// menyentuh layar selama [AppConfig.sessionTimeout], sesi berakhir otomatis. Sebelum itu muncul
/// peringatan "Are you still there?" selama [AppConfig.sessionWarning].
/// Waktu saat app di background ikut dihitung.
class SessionGuard extends StatefulWidget {
  const SessionGuard({super.key, required this.child});

  final Widget child;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> with WidgetsBindingObserver {
  final Session _s = Session.instance;
  Timer? _warnTimer;
  Timer? _expireTimer;
  DateTime _lastActive = DateTime.now();
  bool _warningOpen = false;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _s.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _s.removeListener(_onSessionChanged);
    _cancelTimers();
    super.dispose();
  }

  bool get _signedIn => _s.loggedIn;

  void _onSessionChanged() {
    final now = _signedIn;
    if (now && !_wasSignedIn) {
      _lastActive = DateTime.now();
      _warningOpen = false;
      _schedule();
    } else if (!now && _wasSignedIn) {
      _cancelTimers();
      _warningOpen = false;
    }
    _wasSignedIn = now;
  }

  void _cancelTimers() {
    _warnTimer?.cancel();
    _expireTimer?.cancel();
    _warnTimer = null;
    _expireTimer = null;
  }

  /// Jadwalkan ulang berdasarkan waktu aktivitas terakhir.
  void _schedule() {
    _cancelTimers();
    if (!_signedIn) return;
    final elapsed = DateTime.now().difference(_lastActive);
    if (elapsed >= AppConfig.sessionTimeout) {
      _expire();
      return;
    }
    final untilWarning = AppConfig.sessionTimeout - AppConfig.sessionWarning - elapsed;
    if (untilWarning <= Duration.zero) {
      _showWarning(AppConfig.sessionTimeout - elapsed);
    } else {
      _warnTimer = Timer(untilWarning, () => _showWarning(AppConfig.sessionWarning));
    }
  }

  void _touch() {
    if (!_signedIn || _warningOpen) return; // saat peringatan tampil, hanya tombol yang memperpanjang sesi
    final now = DateTime.now();
    if (now.difference(_lastActive) < const Duration(seconds: 1)) return;
    _lastActive = now;
    _s.saveActivity(now);
    _schedule();
  }

  Future<void> _showWarning(Duration remaining) async {
    if (!_signedIn || _warningOpen) return;
    final navContext = navigatorKey.currentContext;
    if (navContext == null) {
      _expire();
      return;
    }
    _warningOpen = true;
    _expireTimer = Timer(remaining, _expire);

    final stay = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.timer_outlined),
        title: const Text('Are you still there?'),
        content: Text(
          'For your security you will be signed out in ${AppConfig.sessionWarning.inSeconds} seconds '
          'because there was no activity.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Sign out'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stay signed in'),
          ),
        ],
      ),
    );

    if (!_warningOpen) return; // sesi sudah berakhir sendiri saat dialog tampil
    _warningOpen = false;
    if (stay == true) {
      _lastActive = DateTime.now();
      _s.saveActivity(_lastActive, force: true);
      _schedule();
    } else {
      _cancelTimers();
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      await _s.logout();
    }
  }

  void _expire() {
    _cancelTimers();
    _warningOpen = false;
    if (!_signedIn) return;
    navigatorKey.currentState?.popUntil((r) => r.isFirst); // tutup dialog & halaman yang sedang terbuka
    _s.logout(expired: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_signedIn) return;
    if (state == AppLifecycleState.paused) {
      // simpan waktu aktivitas terakhir, supaya sesi bisa dicek saat app dibuka lagi
      _s.saveActivity(_lastActive, force: true);
    } else if (state == AppLifecycleState.resumed) {
      // timer bisa tertunda saat di background -> hitung ulang dari waktu aktivitas terakhir
      if (DateTime.now().difference(_lastActive) >= AppConfig.sessionTimeout) {
        _expire();
      } else if (!_warningOpen) {
        _schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      onPointerUp: (_) => _touch(),
      child: widget.child,
    );
  }
}
