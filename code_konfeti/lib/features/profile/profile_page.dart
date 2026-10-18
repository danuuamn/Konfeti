import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/navigation.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../services/notification_service.dart';
import 'feedback_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';

/// Tab Profile: foto + nama, notifikasi, saran & kesan mata kuliah, pengaturan, dan logout.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploading = false;

  /// avatar_url dari server berbentuk relatif (/uploads/avatars/...), jadi tambahkan alamat server.
  String? _avatarUrl(Map<String, dynamic>? user) {
    final path = user?['avatar_url']?.toString();
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http') ? path : '${AppConfig.apiBase}$path';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.bgAlt,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;

    try {
      // dikecilkan dulu supaya jauh di bawah batas 3 MB di server
      final file = await ImagePicker().pickImage(source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (file == null || !mounted) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      final res = await ApiClient.instance
          .post('/api/auth/me/avatar', <String, Object?>{'image_base64': base64Encode(bytes)});
      Session.instance.updateUser(res as Map);
      _snack('Profile photo updated.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editName() async {
    final current = Session.instance.user?['name']?.toString() ?? '';
    final newName = await showDialog<String>(context: context, builder: (_) => _NameDialog(initial: current));
    if (newName == null || newName.isEmpty || newName == current) return;
    try {
      final res = await ApiClient.instance.put('/api/auth/me', <String, Object?>{'name': newName});
      Session.instance.updateUser(res as Map);
      _snack('Name updated.');
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to see your tickets.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    await Session.instance.logout(); // main.dart otomatis kembali ke halaman login
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  Widget _menu({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
    Color? iconColor,
  }) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      onTap: onTap,
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? AppColors.sun),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.sky, fontSize: 12)),
        trailing: trailing ?? const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: const <Widget>[RotateButton()]),
      body: ListenableBuilder(
        listenable: Session.instance,
        builder: (context, _) {
          final user = Session.instance.user;
          final name = user?['name']?.toString() ?? '-';
          final email = user?['email']?.toString() ?? '';
          final avatar = _avatarUrl(user);

          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: <Widget>[
            Center(
              child: Stack(children: <Widget>[
                CircleAvatar(
                  radius: 56,
                  backgroundColor: AppColors.primary,
                  backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                  onBackgroundImageError: avatar != null ? (_, __) {} : null,
                  child: avatar == null ? const Icon(Icons.person, size: 60, color: AppColors.sky) : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: AppColors.sun,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _uploading ? null : _pickAvatar,
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: _uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                              )
                            : const Icon(Icons.photo_camera, size: 18, color: AppColors.ink),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(tooltip: 'Edit name', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: _editName),
            ]),
            Center(child: Text(email, style: const TextStyle(color: AppColors.sky))),
            const SizedBox(height: 24),
            _menu(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Promos, payment status and reminders',
              onTap: () => _open(const NotificationsPage()),
              trailing: ValueListenableBuilder<int>(
                valueListenable: NotificationService.instance.unread,
                builder: (_, n, __) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  if (n > 0) ...<Widget>[Badge(label: Text('$n')), const SizedBox(width: 8)],
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
            _menu(
              icon: Icons.rate_review_outlined,
              title: 'Course Feedback',
              subtitle: 'Impressions & suggestions for Mobile Application Programming',
              onTap: () => _open(const FeedbackPage()),
            ),
            _menu(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => _open(const SettingsPage()),
            ),
            _menu(
              icon: Icons.logout,
              iconColor: const Color(0xFFFF6B6B),
              title: 'Log out',
              onTap: _logout,
              trailing: const SizedBox.shrink(),
            ),
          ]);
        },
      ),
    );
  }
}

/// Dialog ganti nama. Dibuat sebagai widget sendiri supaya TextEditingController dibuang dengan aman.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Save')),
      ],
    );
  }
}
