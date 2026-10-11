import 'package:flutter/material.dart';

import '../../core/session.dart';

/// SEMENTARA: halaman login/register minimal agar alur bisa dites end-to-end.
/// Ganti dengan halaman login + biometrik buatan Ilham (cukup panggil
/// Session.instance.login/register, lalu main.dart otomatis pindah ke MainShell).
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text('Konfeti', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 24),
              if (_register) ...<Widget>[
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
              ],
              TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (min. 8 characters)')),
              const SizedBox(height: 20),
              FilledButton(
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
    );
  }
}
