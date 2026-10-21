import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Logout otomatis bila tidak ada sentuhan/ketikan selama [AppConfig.sessionTimeout].
/// Sebelumnya muncul peringatan selama [AppConfig.sessionWarning].
class SessionGuard extends StatefulWidget {
  const SessionGuard({super.key, required this.child});
  final Widget child;
  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  Timer? _warn;
  Timer? _expire;
  DateTime _last = DateTime.now();
  bool _dialog = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _warn?.cancel();
    _expire?.cancel();
    super.dispose();
  }

  void _arm() {
    _warn?.cancel();
    _expire?.cancel();
    _warn = Timer(AppConfig.sessionTimeout - AppConfig.sessionWarning, _showWarning);
    _expire = Timer(AppConfig.sessionTimeout, _logout);
  }

  void _activity() {
    final now = DateTime.now();
    if (_dialog || now.difference(_last) < const Duration(seconds: 1)) return;
    _last = now;
    _arm();
  }

  Future<void> _showWarning() async {
    if (!mounted || _dialog) return;
    _dialog = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Masih di sana?'),
        content: Text('Anda akan keluar otomatis dalam ${AppConfig.sessionWarning.inSeconds} detik karena tidak ada aktivitas.'),
        actions: <Widget>[
          TextButton(onPressed: _logout, child: const Text('Keluar')),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tetap masuk')),
        ],
      ),
    );
    _dialog = false;
    _last = DateTime.now();
    if (mounted && Session.instance.loggedIn) _arm();
  }

  void _logout() {
    _warn?.cancel();
    _expire?.cancel();
    if (_dialog && mounted) {
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      _dialog = false;
    }
    Session.instance.logout(notice: 'Sesi berakhir karena tidak ada aktivitas.');
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity(),
      onPointerMove: (_) => _activity(),
      onPointerSignal: (_) => _activity(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, __) {
          _activity();
          return KeyEventResult.ignored;
        },
        child: DefaultTextStyle.merge(style: t(14), child: widget.child),
      ),
    );
  }
}
