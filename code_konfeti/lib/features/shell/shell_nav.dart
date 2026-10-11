import 'package:flutter/foundation.dart';

/// Penghubung antar-halaman untuk pindah tab (mis. selesai checkout -> My Tickets > Pending).
class ShellNav {
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);
  static final ValueNotifier<int> ticketsSubTab = ValueNotifier<int>(0);

  static void goToPending() {
    ticketsSubTab.value = 0;
    tab.value = 1;
  }
}
