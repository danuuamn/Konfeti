import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/server_time.dart';
import '../../core/widgets.dart';

/// Kesan dan saran untuk mata kuliah Pemrograman Aplikasi Mobile (rating 1-5 + pesan).
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _message = TextEditingController();
  int _rating = 0;
  bool _sending = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/api/feedback') as List;
      if (!mounted) return;
      setState(() {
        _items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final text = _message.text.trim();
    if (_rating < 1) {
      _snack('Please give a rating first.');
      return;
    }
    if (text.length < 3) {
      _snack('Please write at least 3 characters.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiClient.instance.post('/api/feedback', <String, Object?>{'rating': _rating, 'message': text});
      if (!mounted) return;
      _message.clear();
      setState(() => _rating = 0);
      FocusScope.of(context).unfocus();
      _snack('Thank you for your feedback!');
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _stars(int value, {double size = 18}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(
          5,
          (i) => Icon(i < value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: AppColors.sun),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Course Feedback')),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('Mobile Application Programming', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Share your impressions and suggestions for this course.',
              style: TextStyle(color: AppColors.sky),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  iconSize: 36,
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppColors.sun,
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Your impressions and suggestions...'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sending ? null : _submit,
                child: Text(_sending ? 'Sending...' : 'Submit'),
              ),
            ),
          ]),
        ),
        const SectionHeader('Your previous feedback', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_error != null)
          Row(children: <Widget>[
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ])
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing sent yet.', style: TextStyle(color: AppColors.sky)),
          )
        else
          for (final f in _items)
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  _stars(((f['rating'] as num?) ?? 0).toInt()),
                  const Spacer(),
                  Text(
                    () {
                      final t = parseServerTime(f['created_at']);
                      return t == null ? '' : DateFormat('d MMM yyyy').format(t);
                    }(),
                    style: const TextStyle(color: AppColors.sky, fontSize: 12),
                  ),
                ]),
                const SizedBox(height: 8),
                Text((f['message'] ?? '').toString(), style: const TextStyle(height: 1.4)),
              ]),
            ),
      ]),
    );
  }
}
