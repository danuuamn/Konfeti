import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../services/local_db.dart';
import '../../services/notification_service.dart';

/// Pengaturan: notifikasi, data lokal (riwayat chat), dan info aplikasi.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifEnabled = true;

  @override
  void initState() {
    super.initState();
    Session.instance.refreshBiometric();
    _load();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    final v = await LocalDb.instance
        .getBool(currentUserId(), NotificationService.settingEnabled, defaultValue: true);
    if (mounted) setState(() => _notifEnabled = v);
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notifEnabled = value);
    await LocalDb.instance.setBool(currentUserId(), NotificationService.settingEnabled, value);
    // saat dimatikan, pengingat lama dibatalkan; saat dinyalakan, dijadwalkan ulang
    await NotificationService.instance.syncReminders();
  }

  Future<void> _toggleBiometric(bool value) async {
    final ok = await Session.instance.setBiometric(value);
    if (!ok) _snack('Biometric setup was cancelled.');
  }

  Future<void> _testNotification() async {
    await NotificationService.instance.showNow('Konfeti test', 'Notifications are working.');
    _snack('Test notification sent.');
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text('All your AI chat messages on this device will be deleted.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await LocalDb.instance.clearChat(currentUserId());
    _snack('Chat history cleared.');
  }

  Widget _group(List<Widget> children) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const SectionHeader('Notifications', padding: EdgeInsets.fromLTRB(0, 4, 0, 10)),
        _group(<Widget>[
          SwitchListTile(
            value: _notifEnabled,
            onChanged: _toggleNotifications,
            title: const Text('Enable notifications'),
            subtitle: const Text(
              'Promos, payment status and event reminders',
              style: TextStyle(color: AppColors.sky, fontSize: 12),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send a test notification'),
            onTap: _testNotification,
          ),
        ]),
        const SectionHeader('Data', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
        _group(<Widget>[
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear AI chat history'),
            subtitle: const Text(
              'Stored only on this device',
              style: TextStyle(color: AppColors.sky, fontSize: 12),
            ),
            onTap: _clearChat,
          ),
        ]),
        const SectionHeader('Security', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
        ListenableBuilder(
          listenable: Session.instance,
          builder: (context, _) {
            final s = Session.instance;
            return _group(<Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint_rounded),
                value: s.bioEnabled,
                onChanged: s.bioAvailable ? _toggleBiometric : null,
                title: const Text('Biometric login (optional)'),
                subtitle: Text(
                  s.bioAvailable
                      ? 'Sign in faster with your fingerprint or face.'
                      : 'Not available on this device.',
                  style: const TextStyle(color: AppColors.sky, fontSize: 12),
                ),
              ),
              if (s.bioEnabled && s.availableMethods.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    const Text('Preferred method', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: <Widget>[
                      for (final m in s.availableMethods)
                        ChoiceChip(
                          avatar: Icon(m == 'face' ? Icons.face_rounded : Icons.fingerprint_rounded, size: 18),
                          label: Text(m == 'face' ? 'Face' : 'Fingerprint'),
                          selected: s.bioMethod == m,
                          selectedColor: AppColors.sun,
                          onSelected: (_) => s.setBioMethod(m),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                      'Your phone shows the final prompt. If you registered both, it may offer either one.',
                      style: TextStyle(fontSize: 12, color: AppColors.sky),
                    ),
                  ]),
                ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Auto sign-out'),
                subtitle: Text(
                  'After ${AppConfig.sessionTimeout.inMinutes} minutes without activity',
                  style: const TextStyle(color: AppColors.sky, fontSize: 12),
                ),
              ),
            ]);
          },
        ),
        const SectionHeader('About', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
        _group(const <Widget>[
          ListTile(
            leading: Icon(Icons.confirmation_number_outlined),
            title: Text('Konfeti'),
            subtitle: Text('Concert & festival ticketing • v0.1.0', style: TextStyle(color: AppColors.sky, fontSize: 12)),
          ),
          ListTile(
            leading: Icon(Icons.dns_outlined),
            title: Text('Server'),
            subtitle: Text(AppConfig.apiBase, style: TextStyle(color: AppColors.sky, fontSize: 12)),
          ),
        ]),
      ]),
    );
  }
}
