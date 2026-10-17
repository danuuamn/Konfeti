import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penanda event favorit (hati di halaman detail). Disimpan lokal di perangkat.
class Favorites {
  static const String _key = 'fav_events';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final ValueNotifier<Set<int>> ids = ValueNotifier<Set<int>>(<int>{});

  static Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) {
        ids.value = (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toSet();
      }
    } catch (_) {/* abaikan data rusak */}
  }

  static Future<void> toggle(int id) async {
    final next = <int>{...ids.value};
    if (!next.remove(id)) next.add(id);
    ids.value = next;
    try {
      await _storage.write(key: _key, value: jsonEncode(next.toList()));
    } catch (_) {}
  }
}
