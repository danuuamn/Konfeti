import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/time_zones.dart';
import 'event_banner.dart';
import 'event_detail_page.dart';

/// Home: pencarian, sorting, filter kategori, lalu Live/Featured, Nearby, dan Upcoming events.
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
  Position? _pos;

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
    _loadLocation();
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

  /// Lokasi user untuk bagian "Nearby Events". Jika ditolak/gagal, bagian itu disembunyikan.
  Future<void> _loadLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 6)),
          );
      if (mounted) setState(() => _pos = pos);
    } catch (_) {/* tanpa lokasi */}
  }

  double? _km(Event e) {
    final p = _pos;
    if (p == null || e.latitude == null || e.longitude == null) return null;
    return Geolocator.distanceBetween(p.latitude, p.longitude, e.latitude!, e.longitude!) / 1000;
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

  void _open(Event e) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => EventDetailPage(event: e)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(child: _header()),
              ..._sections(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Text('Konfeti',
                  style: TextStyle(color: AppColors.sun, fontSize: 28, fontWeight: FontWeight.w800)),
              Text('Find your next concert', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.sky)),
            ]),
          ),
          const RotateButton(),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              setState(() {});
              _onSearchChanged(v);
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search artist or concert',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              fillColor: const Color(0x990E2340),
              prefixIcon: const Icon(Icons.search, color: AppColors.sky),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.sky),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                        _load();
                      }),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: AppColors.skyDim)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: AppColors.skyDim)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: AppColors.sun, width: 1.6)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 16),
            children: <Widget>[
              PopupMenuButton<String>(
                tooltip: 'Sort',
                color: AppColors.bgAlt,
                onSelected: (v) {
                  setState(() => _sort = v);
                  _load();
                },
                itemBuilder: (_) => _sortLabels.entries
                    .map((e) => PopupMenuItem<String>(
                          value: e.key,
                          child: Text(e.value, style: TextStyle(color: e.key == _sort ? AppColors.sun : Colors.white)),
                        ))
                    .toList(),
                child: IgnorePointer(
                  child: CategoryPill(label: _sortLabels[_sort]!, selected: false, icon: Icons.sort),
                ),
              ),
              const SizedBox(width: 8),
              CategoryPill(
                label: 'All',
                selected: _category == null,
                onTap: () {
                  setState(() => _category = null);
                  _load();
                },
              ),
              for (final c in _categories) ...<Widget>[
                const SizedBox(width: 8),
                CategoryPill(
                  label: c,
                  selected: _category == c,
                  onTap: () {
                    setState(() => _category = _category == c ? null : c);
                    _load();
                  },
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  List<Widget> _sections() {
    if (_loading && _events.isEmpty) {
      return const <Widget>[
        SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (_error != null && _events.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ]),
          ),
        ),
      ];
    }
    if (_events.isEmpty) {
      return const <Widget>[
        SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No concerts found.'))),
      ];
    }

    final live = _events.where((e) => e.isLive).toList();
    final hero = live.isNotEmpty ? live.first : _events.first;
    final nearby = _events.where((e) => _km(e) != null).toList()..sort((a, b) => _km(a)!.compareTo(_km(b)!));
    final upcoming = _events.where((e) => e.id != hero.id).toList();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 800 ? 4 : (width > 520 ? 3 : 2);

    return <Widget>[
      SliverToBoxAdapter(child: SectionHeader(live.isNotEmpty ? 'Live Concert' : 'Featured Concert', live: live.isNotEmpty)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _HeroCard(event: hero, live: live.isNotEmpty, onTap: () => _open(hero)),
        ),
      ),
      if (nearby.isNotEmpty) ...<Widget>[
        const SliverToBoxAdapter(child: SectionHeader('Nearby Events')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 228,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: math.min(nearby.length, 8),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _MediumCard(event: nearby[i], km: _km(nearby[i])!, onTap: () => _open(nearby[i])),
            ),
          ),
        ),
      ],
      if (upcoming.isNotEmpty) ...<Widget>[
        const SliverToBoxAdapter(child: SectionHeader('Upcoming Events')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _SmallCard(event: upcoming[i], onTap: () => _open(upcoming[i])),
              childCount: upcoming.length,
            ),
          ),
        ),
      ],
    ];
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.event, required this.live, required this.onTap});
  final Event event;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = zoneParts(event.startUtc, 'Asia/Jakarta');
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 210,
        child: Stack(fit: StackFit.expand, children: <Widget>[
          EventBanner(event: event),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: <Color>[Color(0xE6000000), Color(0x00000000)],
                stops: <double>[0, 0.8],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
              Tag(live ? 'LIVE NOW' : 'FEATURED', icon: live ? Icons.circle : Icons.star_rounded),
              const SizedBox(height: 6),
              Text(event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 2),
              Text('${event.artistLabel} • ${p.date}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              const SizedBox(height: 4),
              Text(rupiah(event.priceIdr),
                  style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
          ),
          Material(color: Colors.transparent, child: InkWell(onTap: onTap)),
        ]),
      ),
    );
  }
}

class _MediumCard extends StatelessWidget {
  const _MediumCard({required this.event, required this.km, required this.onTap});
  final Event event;
  final double km;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          SizedBox(height: 108, child: EventBanner(event: event)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(event.venueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                const Icon(Icons.near_me, size: 14, color: AppColors.sun),
                const SizedBox(width: 4),
                Text('${km.toStringAsFixed(km < 10 ? 1 : 0)} km', style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text(rupiah(event.priceIdr), style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SmallCard extends StatelessWidget {
  const _SmallCard({required this.event, required this.onTap});
  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = zoneParts(event.startUtc, 'Asia/Jakarta');
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(child: SizedBox.expand(child: EventBanner(event: event))),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
            const SizedBox(height: 2),
            Text('${p.day} ${p.month} • ${event.category}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 11)),
            const SizedBox(height: 4),
            Text(rupiah(event.priceIdr), style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
