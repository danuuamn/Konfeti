import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../services/local_db.dart';

/// Tab AI Chat: tanya jawab seputar konser lewat Gemini (proxy backend /api/chat).
/// Riwayat chat disimpan di SQLite lokal per akun, dan 10 pesan terakhir dikirim sebagai konteks.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// Jumlah pesan sebelumnya yang dikirim ke AI sebagai konteks percakapan.
  static const int _contextSize = 10;

  /// Pertanyaan cepat: sekaligus menunjukkan fitur LLM (rekomendasi, perencanaan) tanpa mengetik.
  static const List<String> _suggestions = <String>[
    'What concerts are coming up?',
    'Recommend a concert under Rp 500.000',
    'Which events still have tickets?',
    'What is the cheapest event?',
    'What should I wear to a rock concert?',
    'Tell me about Tulus',
    'Plan my day for a concert',
  ];

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ChatMessage> _messages = <ChatMessage>[];
  bool _loadingHistory = true;
  bool _sending = false;
  String? _error; // gagal mendapat jawaban; tampil sebagai gelembung merah + tombol Retry

  @override
  void initState() {
    super.initState();
    LocalDb.instance.chatVersion.addListener(_loadHistory);
    _loadHistory();
  }

  @override
  void dispose() {
    LocalDb.instance.chatVersion.removeListener(_loadHistory);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadHistory() async {
    try {
      final history = await LocalDb.instance.chatHistory(currentUserId());
      if (!mounted) return;
      setState(() {
        _messages = history;
        _error = null;
      });
      _scrollToEnd(jump: true);
    } catch (_) {
      // database lokal gagal dibuka: chat tetap berjalan tanpa riwayat
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 500) {
      _snack('Message is too long (max 500 characters).');
      return;
    }
    _input.clear();
    final message = ChatMessage(role: 'user', text: text);
    setState(() {
      _messages = <ChatMessage>[..._messages, message];
      _error = null;
    });
    _scrollToEnd();
    try {
      await LocalDb.instance.addChatMessage(currentUserId(), 'user', text);
    } catch (_) {/* riwayat gagal tersimpan, chat tetap lanjut */}
    await _requestReply();
  }

  /// Minta jawaban untuk pesan user terakhir (juga dipakai tombol Retry).
  Future<void> _requestReply() async {
    if (_messages.isEmpty || !_messages.last.isUser) return;
    final question = _messages.last;
    final before = _messages.sublist(0, _messages.length - 1);
    final recent = before.length > _contextSize ? before.sublist(before.length - _contextSize) : before;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.post('/api/chat', <String, Object?>{
        'message': question.text,
        // diabaikan oleh backend lama; dipakai backend yang sudah mendukung konteks percakapan
        'history': recent.map((m) => <String, String>{'role': m.role, 'text': m.text}).toList(),
      }) as Map;
      final reply = (res['reply'] ?? '').toString().trim();
      if (reply.isEmpty) throw ApiException(0, 'The assistant sent an empty answer.');
      if (!mounted) return;
      setState(() => _messages = <ChatMessage>[..._messages, ChatMessage(role: 'model', text: reply)]);
      try {
        await LocalDb.instance.addChatMessage(currentUserId(), 'model', reply);
      } catch (_) {/* abaikan */}
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToEnd();
  }

  static String _friendly(Object e) {
    final s = e.toString();
    return s.length > 180 ? '${s.substring(0, 180)}…' : s;
  }

  /// Gemini sering membalas dengan markdown; tampilkan sebagai teks biasa yang rapi.
  static String _clean(String s) => s
      .replaceAll('**', '')
      .replaceAll(RegExp(r'^#{1,6}[ \t]+', multiLine: true), '')
      .replaceAllMapped(RegExp(r'^[ \t]*[*-][ \t]+', multiLine: true), (_) => '• ')
      .trim();

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new chat?'),
        content: const Text('Your chat history on this device will be deleted.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) await LocalDb.instance.clearChat(currentUserId()); // memicu _loadHistory lewat listener
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: <Widget>[
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _messages.isEmpty ? null : _confirmClear,
          ),
          const RotateButton(),
        ],
      ),
      body: Column(children: <Widget>[
        Expanded(
          child: _loadingHistory
              ? const Center(child: CircularProgressIndicator())
              : (_messages.isEmpty && !_sending ? _emptyState() : _conversation()),
        ),
        _inputBar(),
      ]),
    );
  }

  Widget _emptyState() {
    return ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: <Widget>[
      const Icon(Icons.smart_toy_outlined, size: 64, color: AppColors.sun),
      const SizedBox(height: 14),
      Text(
        'Ask me anything about concerts',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        'Concerts, tickets, songs, artists and concert outfits.\nI only answer topics related to concerts and music. Powered by Gemini.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.sky, height: 1.4),
      ),
      const SizedBox(height: 24),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
        for (final s in _suggestions)
          ActionChip(
            label: Text(s),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
            backgroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.skyFaint),
            onPressed: () => _send(s),
          ),
      ]),
    ]);
  }

  Widget _conversation() {
    return ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), children: <Widget>[
      for (final m in _messages) _bubble(m),
      if (_sending) _typingBubble(),
      if (_error != null) _errorBubble(_error!),
    ]);
  }

  Widget _bubble(ChatMessage m) {
    final user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: user ? AppColors.sun : AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(user ? 16 : 4),
            bottomRight: Radius.circular(user ? 4 : 16),
          ),
        ),
        child: SelectableText(
          user ? m.text : _clean(m.text),
          style: TextStyle(color: user ? AppColors.ink : Colors.white, height: 1.4),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Thinking...', style: TextStyle(color: AppColors.sky)),
        ]),
      ),
    );
  }

  Widget _errorBubble(String message) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(color: const Color(0xFF5C1F28), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(message, style: const TextStyle(color: Color(0xFFFFD9DC), height: 1.4)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _sending ? null : _requestReply, child: const Text('Retry')),
          ),
        ]),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgAlt,
          border: Border(top: BorderSide(color: AppColors.skyFaint)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Ask about concerts, music, artists, outfits...',
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
          ),
        ]),
      ),
    );
  }
}
