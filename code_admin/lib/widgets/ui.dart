import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';

// ---------------------------------------------------------------- feedback

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message, style: t(13, color: error ? C.danger : Colors.white)),
    duration: Duration(seconds: error ? 5 : 3),
  ));
}

String errText(Object e) => e is ApiException ? e.message : 'Terjadi kesalahan. Coba lagi.';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Ya',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(body)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: C.ink) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------- layout

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const <Widget>[]});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: t(22, w: FontWeight.w700)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: t(13, color: C.textSoft))),
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ]),
    );
  }
}

/// Wadah halaman dengan padding standar.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(padding: EdgeInsets.all(narrow ? 16 : 24), child: child);
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
            child: Row(children: <Widget>[
              Expanded(child: Text(title!, style: t(15, w: FontWeight.w600))),
              if (trailing != null) trailing!,
            ]),
          ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.note, this.icon, this.accent = C.sky});
  final String label;
  final String value;
  final String? note;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (icon != null) ...<Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: accent.withAlpha(40), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(label, style: t(12, color: C.textSoft, w: FontWeight.w500)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: t(24, w: FontWeight.w800, nums: true)),
            ),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: t(12, color: C.muted))),
          ]),
        ),
      ]),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? statusColor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(38), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: t(12, w: FontWeight.w600, color: c)),
    );
  }
}

Color statusColor(String s) {
  switch (s) {
    case 'active':
    case 'paid':
    case 'valid':
    case 'checked_in':
      return C.success;
    case 'cancelled':
    case 'failed':
    case 'expired':
      return C.danger;
    case 'admin':
      return C.butter;
    case 'pending':
    case 'draft':
    default:
      return C.muted;
  }
}

// ---------------------------------------------------------------- states

class SkeletonRows extends StatefulWidget {
  const SkeletonRows({super.key, this.rows = 6});
  final int rows;
  @override
  State<SkeletonRows> createState() => _SkeletonRowsState();
}

class _SkeletonRowsState extends State<SkeletonRows> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Column(
        children: List<Widget>.generate(
          widget.rows,
          (i) => Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: C.panel.withAlpha(120 + (_c.value * 100).round()), borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}

class EmptyBox extends StatelessWidget {
  const EmptyBox(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text(text, style: t(14, color: C.textSoft))));
}

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(errText(error), textAlign: TextAlign.center, style: t(14, color: C.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

/// FutureBuilder dengan skeleton / error+Retry / data.
class FutureBody<T> extends StatelessWidget {
  const FutureBody({super.key, required this.future, required this.onRetry, required this.builder, this.skeletonRows = 6});
  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(BuildContext, T) builder;
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return SkeletonRows(rows: skeletonRows);
        if (snap.hasError) return ErrorBox(error: snap.error!, onRetry: onRetry);
        return builder(context, snap.data as T);
      },
    );
  }
}

// ---------------------------------------------------------------- tabel

class Col<R> {
  const Col(this.label, this.cell, {this.width = 120, this.flex = false, this.right = false});
  final String label;
  final Widget Function(R row) cell;
  final double width; // lebar minimum
  final bool flex; // kebagian sisa lebar
  final bool right; // rata kanan (angka)
}

/// Tabel padat: header tetap, baris 46 px. [shrink] true = tinggi mengikuti isi (untuk dipakai di dalam Panel).
class AdminTable<R> extends StatelessWidget {
  const AdminTable({super.key, required this.cols, required this.rows, this.onTap, this.empty = 'Tidak ada data.', this.shrink = false});
  final List<Col<R>> cols;
  final List<R> rows;
  final void Function(R row)? onTap;
  final String empty;
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final minTotal = cols.fold<double>(0, (a, c) => a + c.width) + 24;
      final total = box.maxWidth.isFinite && box.maxWidth > minTotal ? box.maxWidth : minTotal;
      final flexCount = cols.where((c) => c.flex).length;
      final extra = total - minTotal;
      double wOf(Col<R> c) => c.width + (c.flex && flexCount > 0 ? extra / flexCount : 0);

      Widget cell(Col<R> c, Widget child) => SizedBox(
            width: wOf(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Align(alignment: c.right ? Alignment.centerRight : Alignment.centerLeft, child: child),
            ),
          );

      final header = Container(
        height: 40,
        width: total,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(color: C.panel, border: Border(bottom: BorderSide(color: C.line))),
        child: Row(
          children: cols.map((c) => cell(c, Text(c.label, style: t(12, w: FontWeight.w600, color: C.sky), maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
        ),
      );

      Widget rowW(R r) => _Row<R>(row: r, cols: cols, cell: cell, total: total, onTap: onTap);

      final Widget body;
      if (rows.isEmpty) {
        body = SizedBox(width: total, child: EmptyBox(empty));
      } else if (shrink) {
        body = Column(children: rows.map(rowW).toList());
      } else {
        body = Expanded(child: ListView.builder(itemCount: rows.length, itemBuilder: (_, i) => rowW(rows[i])));
      }

      final inner = SizedBox(
        width: total,
        child: Column(mainAxisSize: shrink || rows.isEmpty ? MainAxisSize.min : MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          header,
          body,
        ]),
      );

      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        child: total <= box.maxWidth + 0.5
            ? inner
            : SingleChildScrollView(scrollDirection: Axis.horizontal, child: inner),
      );
    });
  }
}

class _Row<R> extends StatefulWidget {
  const _Row({required this.row, required this.cols, required this.cell, required this.total, this.onTap});
  final R row;
  final List<Col<R>> cols;
  final Widget Function(Col<R>, Widget) cell;
  final double total;
  final void Function(R)? onTap;
  @override
  State<_Row<R>> createState() => _RowState<R>();
}

class _RowState<R> extends State<_Row<R>> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap == null ? null : () => widget.onTap!(widget.row),
        child: Container(
          height: 46,
          width: widget.total,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _hover ? C.primary.withAlpha(40) : Colors.transparent,
            border: const Border(bottom: BorderSide(color: Color(0x1F8ACFF8))),
          ),
          child: Row(children: widget.cols.map((c) => widget.cell(c, c.cell(widget.row))).toList()),
        ),
      ),
    );
  }
}

Widget cellText(String s, {bool nums = false, Color color = Colors.white, bool mono = false}) => Text(
      s,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: mono
          ? const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white)
          : t(13, nums: nums, color: color),
    );

Widget cellTwoLine(String top, String? bottom) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(top, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(13, w: FontWeight.w600)),
        if (bottom != null && bottom.isNotEmpty) Text(bottom, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(12, color: C.textSoft)),
      ],
    );

// ---------------------------------------------------------------- input

class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Cari'});
  final ValueChanged<String> onChanged;
  final String hint;
  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  Timer? _d;
  @override
  void dispose() {
    _d?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextField(
        style: t(14),
        decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search, size: 18, color: C.sky)),
        onChanged: (v) {
          _d?.cancel();
          _d = Timer(const Duration(milliseconds: 350), () => widget.onChanged(v.trim()));
        },
      ),
    );
  }
}

class Pager extends StatelessWidget {
  const Pager({super.key, required this.total, required this.offset, required this.limit, required this.onChange});
  final int total;
  final int offset;
  final int limit;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : offset + 1;
    final to = (offset + limit) > total ? total : offset + limit;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
        Text('$from-$to dari $total', style: t(12, color: C.textSoft, nums: true)),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Sebelumnya',
          onPressed: offset > 0 ? () => onChange((offset - limit).clamp(0, total)) : null,
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        IconButton(
          tooltip: 'Berikutnya',
          onPressed: offset + limit < total ? () => onChange(offset + limit) : null,
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
      ]),
    );
  }
}

/// Pilihan filter berbentuk chip kecil (satu terpilih).
class FilterChips extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.value, required this.onChanged});
  final Map<String, String> options; // nilai -> label
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.entries.map((e) {
        final sel = e.key == value;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? C.primary.withAlpha(64) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sel ? C.sky : C.line),
            ),
            child: Text(e.value, style: t(13, w: FontWeight.w600, color: sel ? Colors.white : C.textSoft)),
          ),
        );
      }).toList(),
    );
  }
}

/// Field berlabel di atas input (untuk form).
class FieldBox extends StatelessWidget {
  const FieldBox({super.key, required this.label, required this.child, this.width});
  final String label;
  final Widget child;
  final double? width;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label, style: t(12, color: C.textSoft, w: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}

/// Paginasi untuk endpoint yang tidak mengirim total: tombol Berikutnya aktif bila halaman terisi penuh.
class PagerLite extends StatelessWidget {
  const PagerLite({super.key, required this.offset, required this.count, required this.limit, required this.onChange});
  final int offset;
  final int count;
  final int limit;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
        Text(count == 0 ? '0' : '${offset + 1}-${offset + count}', style: t(12, color: C.textSoft, nums: true)),
        const SizedBox(width: 8),
        IconButton(tooltip: 'Sebelumnya', onPressed: offset > 0 ? () => onChange((offset - limit).clamp(0, 1 << 30)) : null, icon: const Icon(Icons.chevron_left, size: 20)),
        IconButton(tooltip: 'Berikutnya', onPressed: count >= limit ? () => onChange(offset + limit) : null, icon: const Icon(Icons.chevron_right, size: 20)),
      ]),
    );
  }
}
