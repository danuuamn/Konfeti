import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/time_zones.dart';
import 'event_banner.dart';
import 'event_detail_page.dart';

/// Home: sapaan, pencarian, sorting, filter kategori, lalu Live/Featured, Nearby, dan Upcoming events.
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

  void _open(Event e, String heroTag) => Navigator.push(
      context, MaterialPageRoute<void>(builder: (_) => EventDetailPage(event: e, heroTag: heroTag)));

  String get _firstName {
    final n = Session.instance.user?['name']?.toString().trim() ?? '';
    return n.isEmpty ? 'Friend' : n.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.ink,
            backgroundColor: AppColors.sun,
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
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text('Konfeti', style: AppText.display(size: 22, color: AppColors.sun, weight: FontWeight.w700)),
          ),
          const RotateButton(),
          const SizedBox(width: 8),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text('Hi, $_firstName', style: AppText.display(size: 30, height: 1.15)),
        ),
        const SizedBox(height: 2),
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Text('Find your next concert', style: TextStyle(color: AppColors.sky, fontSize: 14)),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(children: <Widget>[
            Expanded(
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
                  fillColor: AppColors.glass,
                  prefixIcon: const Icon(Icons.search, color: AppColors.sky),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear, color: AppColors.sky),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                            _load();
                          }),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: AppColors.glassBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: AppColors.glassBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: AppColors.sun, width: 1.6)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'Sort: ${_sortLabels[_sort]}',
              color: AppColors.bgAlt,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.glassBorder),
              ),
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
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.tune_rounded, color: AppColors.ink),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 16),
            children: <Widget>[
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
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(children: <Widget>[
              SkeletonBox(height: 220, radius: 24),
              SizedBox(height: 24),
              Row(children: <Widget>[
                Expanded(child: SkeletonBox(height: 170)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 170)),
              ]),
            ]),
          ),
        ),
      ];
    }
    if (_error != null && _events.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(message: _error!, onRetry: _load),
        ),
      ];
    }
    if (_events.isEmpty) {
      return const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No concerts found',
            subtitle: 'Try another keyword or category.',
          ),
        ),
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
          child: _HeroCard(event: hero, live: live.isNotEmpty, onTap: () => _open(hero, 'hero-${hero.id}')),
        ),
      ),
      if (nearby.isNotEmpty) ...<Widget>[
        const SliverToBoxAdapter(child: SectionHeader('Nearby Events')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 232,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: math.min(nearby.length, 8),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _MediumCard(
                event: nearby[i],
                km: _km(nearby[i])!,
                onTap: () => _open(nearby[i], 'near-${nearby[i].id}'),
              ),
            ),
          ),
        ),
      ],
      if (upcoming.isNotEmpty) ...<Widget>[
        const SliverToBoxAdapter(child: SectionHeader('Upcoming Events')),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, navBottomSpace(context)),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _SmallCard(event: upcoming[i], onTap: () => _open(upcoming[i], 'grid-${upcoming[i].id}')),
              childCount: upcoming.length,
            ),
          ),
        ),
      ] else
        SliverToBoxAdapter(child: SizedBox(height: navBottomSpace(context))),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x59006199), blurRadius: 28, spreadRadius: -6)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 220,
          child: Stack(fit: StackFit.expand, children: <Widget>[
            EventBanner(event: event, heroTag: 'hero-${event.id}'),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[Color(0xF0050D1A), Color(0x00050D1A)],
                  stops: <double>[0, 0.85],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                Tag(live ? 'LIVE NOW' : 'FEATURED',
                    icon: live ? Icons.circle : Icons.star_rounded, color: live ? AppColors.danger : AppColors.butter),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.display(size: 22, height: 1.15)),
                      const SizedBox(height: 4),
                      Text('${event.artistLabel} • ${p.date}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.sky, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(rupiah(event.priceIdr),
                          style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(color: AppColors.sun, shape: BoxShape.rectangle, borderRadius: BorderRadius.all(Radius.circular(999))),
                    child: Text(event.soldOut ? 'Sold out' : 'Get Tickets',
                        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ]),
              ]),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                    border: Border.fromBorderSide(BorderSide(color: AppColors.glow, width: 1.2)),
                  ),
                ),
              ),
            ),
            Material(color: Colors.transparent, child: InkWell(onTap: onTap)),
          ]),
        ),
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
          SizedBox(height: 112, width: double.infinity, child: EventBanner(event: event, heroTag: 'near-${event.id}')),
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
                Text(rupiah(event.priceIdr), style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w800, fontSize: 12)),
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
        Expanded(child: SizedBox.expand(child: EventBanner(event: event, heroTag: 'grid-${event.id}'))),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
            const SizedBox(height: 2),
            Text('${p.day} ${p.month} • ${event.category}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 11)),
            const SizedBox(height: 4),
            Text(rupiah(event.priceIdr), style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
