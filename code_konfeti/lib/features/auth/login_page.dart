import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';

/// Halaman login/register (gaya Night Confetti: dark, kaca, tombol kuning di bawah).
/// Tetap memakai Session.login/register; jika halaman login + biometrik Ilham sudah ada,
/// cukup ganti file ini (main.dart otomatis pindah ke MainShell saat login berhasil).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // App dibuka dengan biometrik aktif -> langsung munculkan prompt sidik jari/wajah.
    if (Session.instance.promptBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _biometric();
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_register) {
        await Session.instance.register(_name.text.trim(), _email.text.trim(), _password.text);
      } else {
        await Session.instance.login(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometric() async {
    setState(() => _busy = true);
    try {
      await Session.instance.loginWithBiometric();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      const Align(alignment: Alignment.centerRight, child: RotateButton()),
                      const SizedBox(height: 8),
                      Center(
                        child: KonfetiLogo(size: 124),
                      ),
                      const SizedBox(height: 14),
                      Text('Konfeti',
                          textAlign: TextAlign.center,
                          style: AppText.display(size: 38, color: AppColors.sun, weight: FontWeight.w700)),
                      ListenableBuilder(
                        listenable: Session.instance,
                        builder: (context, _) {
                          if (!Session.instance.sessionExpired) return const SizedBox(height: 28);
                          return Container(
                            margin: const EdgeInsets.only(top: 18, bottom: 6),
                            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                            decoration: BoxDecoration(
                              color: AppColors.glass,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.sun),
                            ),
                            child: Row(children: <Widget>[
                              const Icon(Icons.timer_outlined, size: 20, color: AppColors.sun),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your session has ended (no activity for ${AppConfig.sessionTimeout.inMinutes} minutes, '
                                  'or it expired). Please sign in again.',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: Session.instance.clearSessionExpired,
                              ),
                            ]),
                          );
                        },
                      ),
                      Text('Welcome to Konfeti', textAlign: TextAlign.center, style: AppText.display(size: 26)),
                      const SizedBox(height: 6),
                      const Text('Discover concerts, book tickets, and enjoy the show.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.sky)),
                      const SizedBox(height: 28),
                      GlassCard(
                        blur: true,
                        padding: const EdgeInsets.all(16),
                        child: Column(children: <Widget>[
                          if (_register) ...<Widget>[
                        TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline))),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
                      const SizedBox(height: 14),
                      TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                              labelText: 'Password (min. 8 characters)', prefixIcon: Icon(Icons.lock_outline))),
                        ]),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Please wait...' : (_register ? 'Create account' : 'Login')),
                      ),
                      ListenableBuilder(
                        listenable: Session.instance,
                        builder: (context, _) {
                          final s = Session.instance;
                          if (!(s.hasBioToken && s.bioAvailable)) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _biometric,
                              icon: Icon(s.bioMethod == 'face' ? Icons.face_rounded : Icons.fingerprint_rounded),
                              label: Text('Sign in with ${s.bioLabel}'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            ),
                          );
                        },
                      ),
                      TextButton(
                        onPressed: () => setState(() => _register = !_register),
                        child: Text(_register ? 'I already have an account' : 'Create a new account'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
