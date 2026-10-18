import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
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
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: const BoxDecoration(
                            color: AppColors.sun,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[BoxShadow(color: Color(0x66FFD444), blurRadius: 32, spreadRadius: -4)],
                          ),
                          child: const Icon(Icons.celebration, size: 44, color: AppColors.ink),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Konfeti',
                          textAlign: TextAlign.center,
                          style: AppText.display(size: 38, color: AppColors.sun, weight: FontWeight.w700)),
                      const SizedBox(height: 28),
                      Text('Welcome to Konfeti', textAlign: TextAlign.center, style: AppText.display(size: 26)),
                      const SizedBox(height: 6),
                      const Text('Discover concerts, book tickets, and enjoy the show.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.sky)),
                      const SizedBox(height: 28),
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
                      const Spacer(),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Please wait...' : (_register ? 'Create account' : 'Login')),
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
