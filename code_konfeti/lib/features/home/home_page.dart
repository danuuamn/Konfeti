import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../models/event.dart';
import '../../services/time_zones.dart';
import 'event_detail_page.dart';

/// Home: daftar konser + pencarian + sorting + filter kategori.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<Event> _events = <Event>[];
  List<String> _categories = <String>[];
  String? _category;
  String _sort = 'start';
  bool _loading = true;
  String? _error;

  static const Map<String, String> _sortLabels = <String, String>{
    'start': 'Soonest',
    'price_asc': 'Price: low to high',
    'price_desc': 'Price: high to low',
  };

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await ApiClient.instance.get('/api/events/categories') as List;
      if (mounted) setState(() => _categories = data.whereType<String>().toList());
    } catch (_) {/* filter kategori opsional */}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.get('/api/events', query: <String, String>{
        'q': _search.text.trim(),
        'sort': _sort,
        if (_category != null) 'category': _category!,
      }) as List;
      final list = data
          .map((e) => Event.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((e) => !e.hasEnded) // event yang sudah selesai tidak dijual lagi
          .toList();
      if (mounted) setState(() => _events = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konfeti')),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search artist or concert',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _load();
                      }),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: <Widget>[
              PopupMenuButton<String>(
                tooltip: 'Sort',
                onSelected: (v) {
                  setState(() => _sort = v);
                  _load();
                },
                itemBuilder: (_) => _sortLabels.entries
                    .map((e) => PopupMenuItem<String>(value: e.key, child: Text(e.value)))
                    .toList(),
                child: Chip(avatar: const Icon(Icons.sort, size: 18), label: Text(_sortLabels[_sort]!)),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All'),
                selected: _category == null,
                onSelected: (_) {
                  setState(() => _category = null);
                  _load();
                },
              ),
              for (final c in _categories) ...<Widget>[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) {
                    setState(() => _category = _category == c ? null : c);
                    _load();
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading && _events.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _events.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _events.isEmpty
          ? ListView(children: const <Widget>[
              SizedBox(height: 120),
              Center(child: Text('No concerts found.')),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _events.length,
              itemBuilder: (_, i) => _EventCard(
                event: _events[i],
                onTap: () => Navigator.push(
                    context, MaterialPageRoute<void>(builder: (_) => EventDetailPage(event: _events[i]))),
              ),
            ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});
  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wib = convertToZone(event.startUtc, 'Asia/Jakarta');
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          EventBanner(event: event, height: 110),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(event.title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('${event.artist} • ${event.category}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Row(children: <Widget>[
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(event.venueName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 2),
              Row(children: <Widget>[
                const Icon(Icons.event_outlined, size: 16),
                const SizedBox(width: 4),
                Text('${wib.text} ${wib.abbr}'),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
                Text(rupiah(event.priceIdr),
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                if (event.soldOut)
                  const Text('Sold out', style: TextStyle(color: Colors.red))
                else
                  Text('${event.stock} left', style: theme.textTheme.bodySmall),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Banner event: pakai gambar jika ada, kalau tidak gradient berdasarkan kategori.
class EventBanner extends StatelessWidget {
  const EventBanner({super.key, required this.event, this.height = 160});
  final Event event;
  final double height;

  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF7C3AED), Color(0xFFEC4899)],
    <Color>[Color(0xFF0EA5E9), Color(0xFF6366F1)],
    <Color>[Color(0xFFF97316), Color(0xFFEF4444)],
    <Color>[Color(0xFF10B981), Color(0xFF0EA5E9)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[event.category.hashCode.abs() % _palettes.length];
    final url = event.imageUrl;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      child: url != null && url.startsWith('http')
          ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback())
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
        child: Text(event.artist,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      );
}
