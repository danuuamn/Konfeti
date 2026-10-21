import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/ui.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await Api.instance.get('/api/admin/dashboard') as Map);

  void _reload() => setState(() {
    _f = _load();
  });

  static const List<String> _days = <String>['Senin', 'Selasa', 'Rabu', 'Kamis', "Jumat", 'Sabtu', 'Minggu'];
  static const List<String> _months = <String>[
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  String _today() {
    final n = DateTime.now();
    return '${_days[n.weekday - 1]}, ${n.day} ${_months[n.month - 1]} ${n.year}';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      child: ListView(children: <Widget>[
        FutureBody<Map<String, dynamic>>(
          future: _f,
          onRetry: _reload,
          builder: (c, d) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            _hero(d),
            const SizedBox(height: 16),
            _content(d),
          ]),
        ),
      ]),
    );
  }

  /// Banner sapaan + aksi cepat. Warna solid dengan confetti datar.
  Widget _hero(Map<String, dynamic> d) {
    final name = (Session.instance.user?.name ?? 'Admin').split(' ').first;
    final open = asInt(d['open_alerts']);
    return ConfettiBanner(
      radius: 14,
      seed: 5,
      count: 38,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(_today(), style: t(12, color: Colors.white.withAlpha(200), w: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${_greeting()}, $name', style: t(24, w: FontWeight.w800)),
              ]),
            ),
            IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh, color: Colors.white)),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
            FilledButton.icon(onPressed: () => goAdmin('checkin'), icon: const Icon(Icons.qr_code_scanner, size: 18), label: const Text('Scan tiket')),
            _heroBtn(Icons.event_outlined, 'Events', () => goAdmin('events')),
            _heroBtn(Icons.receipt_long_outlined, 'Orders', () => goAdmin('orders')),
            _heroBtn(Icons.warning_amber_outlined, open > 0 ? 'SOS ($open)' : 'SOS', () => goAdmin('emergency'), alert: open > 0),
          ]),
        ]),
      ),
    );
  }

  Widget _heroBtn(IconData icon, String label, VoidCallback onTap, {bool alert = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: alert ? C.danger : Colors.white),
      label: Text(label, style: t(14, w: FontWeight.w700, color: alert ? C.danger : Colors.white)),
      style: OutlinedButton.styleFrom(
        backgroundColor: C.bg.withAlpha(alert ? 230 : 110),
        side: BorderSide(color: alert ? C.danger : Colors.white.withAlpha(120)),
      ),
    );
  }

  /// "Perlu perhatian": hal yang harus ditindaklanjuti admin, masing-masing menuju halaman terkait.
  Widget _attention(Map<String, dynamic> d, int lowCount) {
    final open = asInt(d['open_alerts']);
    final pending = asInt(d['pending_orders']);
    final items = <Widget>[
      if (open > 0) _attnRow(Icons.warning_amber_rounded, C.danger, '$open alert SOS belum ditangani', 'emergency'),
      if (pending > 0) _attnRow(Icons.hourglass_top, C.sun, '$pending order menunggu pembayaran', 'orders'),
      if (lowCount > 0) _attnRow(Icons.inventory_2_outlined, C.butter, '$lowCount event dengan stok menipis', 'events'),
    ];
    return Panel(
      title: 'Perlu perhatian',
      child: items.isEmpty
          ? Row(children: <Widget>[
              const Icon(Icons.check_circle_outline, size: 20, color: C.success),
              const SizedBox(width: 10),
              Expanded(child: Text('Semua aman. Tidak ada yang perlu ditindaklanjuti.', style: t(14, color: C.textSoft))),
            ])
          : Column(children: items),
    );
  }

  Widget _attnRow(IconData icon, Color color, String text, String target) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => goAdmin(target),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: t(14, w: FontWeight.w600))),
          const Icon(Icons.chevron_right, size: 18, color: C.sky),
        ]),
      ),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final sold = asInt(d['tickets_sold']);
    final checked = asInt(d['tickets_checked_in']);
    final sales = (d['sales_by_day'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final top = (d['top_events'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final low = (d['low_stock'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final byStatus = (d['orders_by_status'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 480 ? 2 : 1);
        final w = (box.maxWidth - (cols - 1) * 12) / cols;
        final cards = <Widget>[
          StatCard(label: 'Revenue', value: rp(d['revenue_idr']), note: 'Order berstatus paid', icon: Icons.payments_outlined, accent: C.sun),
          StatCard(label: 'Tickets sold', value: num0(sold), note: '${num0(d['users'])} user terdaftar', icon: Icons.confirmation_number_outlined, accent: C.sky),
          StatCard(label: 'Checked in', value: num0(checked), note: sold == 0 ? null : '${(checked * 100 / sold).toStringAsFixed(0)}% dari tiket terjual', icon: Icons.how_to_reg_outlined, accent: C.success),
          StatCard(label: 'Active events', value: num0(d['active_events']), note: 'Belum selesai', icon: Icons.event_available_outlined, accent: C.butter),
        ];
        return Wrap(spacing: 12, runSpacing: 12, children: cards.map((c) => SizedBox(width: w, child: c)).toList());
      }),
      const SizedBox(height: 16),
      _attention(d, low.length),
      const SizedBox(height: 16),
      Panel(
        title: 'Penjualan 14 hari terakhir',
        child: SizedBox(height: 220, child: sales.isEmpty ? const EmptyBox('Belum ada penjualan dalam 14 hari terakhir.') : _chart(sales)),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, box) {
        final two = box.maxWidth >= 800;
        final topPanel = Panel(
          title: 'Top events',
          padding: const EdgeInsets.all(12),
          child: AdminTable<Map<String, dynamic>>(
            shrink: true,
            empty: 'Belum ada event.',
            rows: top,
            cols: <Col<Map<String, dynamic>>>[
              Col('Event', (r) => cellTwoLine('${r['title']}', '${r['artist'] ?? ''}'), width: 180, flex: true),
              Col('Terjual', (r) => cellText(num0(r['tickets_sold']), nums: true), width: 80, right: true),
            ],
          ),
        );
        final lowPanel = Panel(
          title: 'Stok menipis (<= 20)',
          padding: const EdgeInsets.all(12),
          child: AdminTable<Map<String, dynamic>>(
            shrink: true,
            empty: 'Tidak ada event dengan stok menipis.',
            rows: low,
            cols: <Col<Map<String, dynamic>>>[
              Col('Event', (r) => cellText('${r['title']}'), width: 180, flex: true),
              Col('Stok', (r) => cellText(num0(r['stock']), nums: true, color: asInt(r['stock']) == 0 ? C.danger : Colors.white), width: 70, right: true),
            ],
          ),
        );
        if (two) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(child: topPanel),
            const SizedBox(width: 12),
            Expanded(child: lowPanel),
          ]);
        }
        return Column(children: <Widget>[topPanel, const SizedBox(height: 12), lowPanel]);
      }),
      const SizedBox(height: 16),
      Panel(
        title: 'Order per status',
        child: byStatus.isEmpty
            ? const Text('Belum ada order.')
            : Wrap(spacing: 20, runSpacing: 10, children: byStatus.map((s) {
                return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  StatusBadge('${s['status']}'),
                  const SizedBox(width: 8),
                  Text(num0(s['n']), style: t(15, w: FontWeight.w700, nums: true)),
                ]);
              }).toList()),
      ),
    ]);
  }

  Widget _chart(List<Map<String, dynamic>> sales) {
    final maxY = sales.map((s) => asInt(s['revenue'])).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: Color(0x1F8ACFF8), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(_short(v), style: t(10, color: C.muted, nums: true)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= sales.length) return const SizedBox.shrink();
                if (sales.length > 8 && i % 2 == 1) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(fmtDay(sales[i]['day']), style: t(10, color: C.muted)));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => C.bg,
            getTooltipItem: (group, gi, rod, ri) {
              final s = sales[group.x];
              return BarTooltipItem('${fmtDay(s['day'])}\n${rp(s['revenue'])}\n${s['orders']} order', t(12));
            },
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (var i = 0; i < sales.length; i++)
            BarChartGroupData(x: i, barRods: <BarChartRodData>[
              BarChartRodData(toY: asInt(sales[i]['revenue']).toDouble(), color: C.sun, width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
            ]),
        ],
      ),
    );
  }

  String _short(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(v % 1e6 == 0 ? 0 : 1)} jt';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)} rb';
    return v.toStringAsFixed(0);
  }
}
