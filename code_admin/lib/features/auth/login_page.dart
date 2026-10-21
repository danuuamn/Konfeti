import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Email dan password wajib diisi.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.login(email, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const List<(IconData, String)> _features = <(IconData, String)>[
    (Icons.qr_code_scanner, 'Check-in tiket dengan scan QR'),
    (Icons.event_outlined, 'Kelola konser, kategori, dan stok'),
    (Icons.link, 'Keaslian tiket tercatat di blockchain'),
    (Icons.warning_amber_outlined, 'Pantau dan tanggapi alert SOS penonton'),
  ];

  Widget _brandContent({required bool wide}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 56 : 24, wide ? 56 : 28, wide ? 56 : 24, wide ? 56 : 28),
      child: Column(
        mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Row(children: <Widget>[
            BrandLogo(size: wide ? 72 : 56),
            const SizedBox(width: 14),
            Text('Konfeti', style: t(wide ? 34 : 28, w: FontWeight.w800, color: C.sun)),
          ]),
          SizedBox(height: wide ? 28 : 16),
          Text('Panel admin', style: t(wide ? 40 : 26, w: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Kelola konser, tiket, dan keselamatan penonton dari satu tempat.',
            style: t(wide ? 16 : 14, color: Colors.white.withAlpha(220)),
          ),
          if (wide) ...<Widget>[
            const SizedBox(height: 32),
            for (final f in _features)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: C.bg.withAlpha(90), borderRadius: BorderRadius.circular(10)),
                    child: Icon(f.$1, size: 18, color: C.sun),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f.$2, style: t(14, w: FontWeight.w600))),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _form() {
    final notice = Session.instance.notice;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Masuk', style: t(24, w: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Gunakan akun admin Konfeti.', style: t(14, color: C.textSoft)),
          const SizedBox(height: 24),
          if (notice != null && _error == null) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.butter.withAlpha(30), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.butter.withAlpha(120))),
              child: Row(children: <Widget>[
                const Icon(Icons.info_outline, size: 16, color: C.butter),
                const SizedBox(width: 8),
                Expanded(child: Text(notice, style: t(13, color: C.butter))),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          FieldBox(
            label: 'Email',
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.username],
              textInputAction: TextInputAction.next,
              style: t(14),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline, size: 18, color: C.sky)),
            ),
          ),
          const SizedBox(height: 14),
          FieldBox(
            label: 'Password',
            child: TextField(
              controller: _pass,
              obscureText: _hide,
              autofillHints: const <String>[AutofillHints.password],
              onSubmitted: (_) => _submit(),
              style: t(14),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline, size: 18, color: C.sky),
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Tampilkan' : 'Sembunyikan',
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: C.sky),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Icon(Icons.error_outline, size: 16, color: C.danger),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!, style: t(13, color: C.danger))),
            ]),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink))
                  : const Text('Masuk'),
            ),
          ),
          const SizedBox(height: 18),
          Text('Akun admin dibuat lewat backend: dart run bin/create_admin.dart', style: t(12, color: C.muted)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(children: <Widget>[
          Expanded(flex: 5, child: ConfettiBanner(seed: 11, count: 70, child: _brandContent(wide: true))),
          Expanded(flex: 4, child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(40), child: _form()))),
        ]),
      );
    }
    return Scaffold(
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            ConfettiBanner(
              seed: 11,
              count: 34,
              child: SafeArea(bottom: false, child: _brandContent(wide: false)),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 32), child: Center(child: _form())),
          ]),
        ),
      ),
    );
  }
}
