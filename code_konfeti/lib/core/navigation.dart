import 'package:flutter/material.dart';

/// Kunci global agar layanan di luar widget (mis. sensor) bisa menampilkan dialog/snackbar di halaman mana pun.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
