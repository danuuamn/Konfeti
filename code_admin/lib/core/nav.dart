import 'package:flutter/foundation.dart';

/// Permintaan pindah menu dari halaman mana pun (mis. tombol di dashboard).
/// AdminShell mendengarkan ini dan menampilkan halaman yang diminta.
final ValueNotifier<String?> adminNav = ValueNotifier<String?>(null);

void goAdmin(String id) {
  adminNav.value = null; // reset supaya permintaan yang sama dua kali tetap terbaca
  adminNav.value = id;
}
