import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db.dart';
import '../env.dart';
import '../errors.dart';
import '../web.dart';

/// Memanggil Gemini lewat REST. Melempar [ApiError] dengan status HTTP dari Google.
Future<String> _generate(String model, String instruction, List<Map<String, String>> turns) async {
  final resp = await http
      .post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'x-goog-api-key': Env.get('GEMINI_API_KEY'),
        },
        body: jsonEncode(<String, Object?>{
          'systemInstruction': <String, Object?>{
            'parts': <Object?>[<String, Object?>{'text': instruction}],
          },
          'contents': turns
              .map((t) => <String, Object?>{
                    'role': t['role'],
                    'parts': <Object?>[<String, Object?>{'text': t['text']}],
                  })
              .toList(),
        }),
      )
      .timeout(const Duration(seconds: 60));

  final text = utf8.decode(resp.bodyBytes);
  if (resp.statusCode != 200) {
    var msg = text;
    try {
      final j = jsonDecode(text);
      if (j is Map && j['error'] is Map && (j['error'] as Map)['message'] is String) {
        msg = (j['error'] as Map)['message'] as String;
      }
    } catch (_) {}
    throw ApiError(resp.statusCode, '[${resp.statusCode}] $msg');
  }

  final j = jsonDecode(text);
  final buffer = StringBuffer();
  if (j is Map && j['candidates'] is List && (j['candidates'] as List).isNotEmpty) {
    final cand = (j['candidates'] as List).first;
    final content = cand is Map ? cand['content'] : null;
    final parts = content is Map ? content['parts'] : null;
    if (parts is List) {
      for (final p in parts) {
        if (p is Map && p['text'] is String) buffer.write(p['text'] as String);
      }
    }
  }
  final reply = buffer.toString();
  if (reply.trim().isEmpty) throw ApiError(0, 'Gemini returned an empty or blocked response');
  return reply;
}

// Proxy Gemini: API key hanya ada di server
void registerChat(Router r, AppDb db) {
  r.post('/api/chat', (c) async {
    final message = c.bodyMap['message'];
    if (message is! String || message.trim().isEmpty || message.length > 500) {
      await c.json(400, <String, Object?>{'message': 'Invalid message (1-500 chars)'});
      return;
    }
    if (!Env.has('GEMINI_API_KEY')) {
      await c.json(503, <String, Object?>{'message': 'GEMINI_API_KEY is not set in .env'});
      return;
    }

    // Beri konteks data event dari database agar jawaban relevan
    final events = await db.all(
      'SELECT title, artist, category, venue_name, start_time_utc, price_idr, stock FROM events',
    );
    final instruction = 'You are a helpful assistant for a concert ticketing app called Konfeti. '
        'Reply in the same language the user writes in (Indonesian or English). Keep answers short. '
        'Use only this event data when answering about concerts (prices are in IDR): ${jsonEncode(events)}';
    final turns = <Map<String, String>>[];
    final h = c.bodyMap['history'];
    if (h is List) {
      final recent = h.length > 10 ? h.sublist(h.length - 10) : h;
      for (final x in recent) {
        if (x is! Map) continue;
        final role = x['role'];
        final text = x['text'];
        if ((role != 'user' && role != 'model') || text is! String || text.trim().isEmpty) continue;
        if (turns.isEmpty && role == 'model') continue; // percakapan harus dimulai dari user
        turns.add(<String, String>{'role': role as String, 'text': text.length > 500 ? text.substring(0, 500) : text});
      }
    }
    turns.add(<String, String>{'role': 'user', 'text': message});
    final primary = Env.get('GEMINI_MODEL', 'gemini-flash-latest');
    final fallback = Env.get('GEMINI_FALLBACK_MODEL', 'gemini-2.5-flash-lite');
    final attempts = <String>[primary, primary, fallback];

    Object? lastError;
    for (final name in attempts) {
      try {
        final reply = await _generate(name, instruction, turns);
        await c.json(200, <String, Object?>{'reply': reply});
        return;
      } catch (e) {
        lastError = e;
        final status = e is ApiError ? e.status : null;
        print('Gemini error ($name): $status $e');
        if (status != 503 && status != 429) break; // ulangi hanya jika server sibuk / kuota
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }

    final err = lastError;
    final status = err is ApiError && err.status != 0 ? err.status.toString() : 'error';
    var detail = err == null ? '' : err.toString();
    if (detail.length > 200) detail = detail.substring(0, 200);
    await c.json(502, <String, Object?>{'message': 'AI service busy, please try again. ($status) $detail'});
  }, auth: true);
}
