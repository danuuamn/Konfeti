import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/server_time.dart';
import '../../core/widgets.dart';
import '../../services/notification_service.dart';

/// Daftar notifikasi dari server (promo, status pembayaran, darurat). Ketuk untuk menandai dibaca.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isUnread(Map<String, dynamic> n) => ((n['is_read'] as num?)?.toInt() ?? 0) == 0;

  /// Sinkronkan angka badge di tab Profile dengan daftar yang sedang ditampilkan.
  void _syncBadge() => NotificationService.instance.unread.value = _items.where(_isUnread).length;

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/api/notifications') as List;
      if (!mounted) return;
      setState(() {
        _items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
      _syncBadge();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (!_isUnread(n)) return;
    setState(() => n['is_read'] = 1);
    _syncBadge();
    try {
      await ApiClient.instance.post('/api/notifications/${n['id']}/read');
    } catch (_) {
      if (!mounted) return;
      setState(() => n['is_read'] = 0); // gagal: kembalikan
      _syncBadge();
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.instance.post('/api/notifications/read-all');
      if (!mounted) return;
      setState(() {
        for (final n in _items) {
          n['is_read'] = 1;
        }
      });
      _syncBadge();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any(_isUnread);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          if (hasUnread) TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
                    FilledButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: const <Widget>[
                          SizedBox(height: 120),
                          Icon(Icons.notifications_none, size: 56, color: AppColors.skyDim),
                          SizedBox(height: 12),
                          Center(child: Text('No notifications yet.', style: TextStyle(color: AppColors.sky))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _tile(_items[i]),
                        ),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final unread = _isUnread(n);
    final time = parseServerTime(n['created_at']);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _markRead(n),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 12),
          child: Icon(Icons.circle, size: 10, color: unread ? AppColors.sun : Colors.transparent),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(
              (n['title'] ?? '').toString(),
              style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text((n['body'] ?? '').toString(), style: const TextStyle(color: AppColors.sky, height: 1.4)),
            if (time != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                DateFormat('d MMM • HH:mm').format(time),
                style: const TextStyle(color: AppColors.skyDim, fontSize: 11),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
