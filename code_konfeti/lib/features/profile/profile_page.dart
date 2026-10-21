import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/navigation.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../services/local_db.dart';
import '../../services/notification_service.dart';
import 'notifications_page.dart';
import 'settings_page.dart';

/// Tab Profile: foto + nama, kartu kesan & pesan mata kuliah (bisa diedit), notifikasi, pengaturan, dan logout.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploading = false;
  Map<String, dynamic>? _note; // kesan & pesan terbaru (null = belum pernah menulis)
  bool _noteLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  /// Ambil kesan & pesan terbaru dari server; bila offline pakai salinan di HP.
  Future<void> _loadNote() async {
    try {
      final list = await ApiClient.instance.get('/api/feedback') as List;
      final latest = list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
      try {
        await LocalDb.instance.putCache(currentUserId(), 'feedback', jsonEncode(latest));
      } catch (_) {}
      if (mounted) setState(() => _note = latest);
    } catch (_) {
      try {
        final raw = await LocalDb.instance.getCache(currentUserId(), 'feedback');
        final j = raw == null ? null : jsonDecode(raw);
        if (mounted && j is Map) setState(() => _note = Map<String, dynamic>.from(j));
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _noteLoading = false);
    }
  }

  Future<void> _editNote() async {
    final result = await showDialog<({int rating, String message})>(
      context: context,
      builder: (_) => _NoteDialog(
        initialRating: ((_note?['rating'] as num?) ?? 0).toInt(),
        initialMessage: (_note?['message'] ?? '').toString(),
      ),
    );
    if (result == null) return;
    try {
      final body = <String, Object?>{'rating': result.rating, 'message': result.message};
      final id = (_note?['id'] as num?)?.toInt();
      final res = id == null
          ? await ApiClient.instance.post('/api/feedback', body)
          : await ApiClient.instance.put('/api/feedback/$id', body);
      final saved = Map<String, dynamic>.from(res as Map);
      try {
        await LocalDb.instance.putCache(currentUserId(), 'feedback', jsonEncode(saved));
      } catch (_) {}
      if (mounted) setState(() => _note = saved);
      _snack('Saved.');
    } catch (e) {
      _snack(e.toString());
    }
  }

  /// Kartu deskripsi "Kesan & Pesan" mata kuliah Pemrograman Aplikasi Mobile (bisa diedit).
  Widget _noteCard() {
    final rating = ((_note?['rating'] as num?) ?? 0).toInt();
    final message = (_note?['message'] ?? '').toString();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Expanded(
            child: Text('Impressions & Message',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: _noteLoading ? null : _editNote,
          ),
        ]),
        const Text('Mobile Application Programming', style: TextStyle(color: AppColors.sky, fontSize: 12)),
        const SizedBox(height: 8),
        if (_noteLoading)
          const SizedBox(height: 20, child: LinearProgressIndicator())
        else if (_note == null)
          GestureDetector(
            onTap: _editNote,
            child: const Text('Tap to write your impressions and message for this course.',
                style: TextStyle(color: AppColors.skyDim, height: 1.4)),
          )
        else ...<Widget>[
          Row(children: <Widget>[
            for (var i = 1; i <= 5; i++)
              Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: AppColors.sun),
          ]),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(height: 1.45)),
        ],
      ]),
    );
  }

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
            const SizedBox(height: 20),
            _noteCard(),
            const SizedBox(height: 20),
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

/// Dialog tulis/ubah kesan & pesan: bintang 1-5 + teks.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initialRating, required this.initialMessage});
  final int initialRating;
  final String initialMessage;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialMessage);
  late int _rating = widget.initialRating;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (_rating < 1) {
      setState(() => _error = 'Please give a rating first.');
      return;
    }
    if (text.length < 3) {
      setState(() => _error = 'Please write at least 3 characters.');
      return;
    }
    Navigator.pop(context, (rating: _rating, message: text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Impressions & Message'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i star${i == 1 ? '' : 's'}',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _rating = i),
                icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.sun, size: 30),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: 'Your impressions and message...', errorText: _error),
          ),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}