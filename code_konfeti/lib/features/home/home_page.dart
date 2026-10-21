import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/local_db.dart';
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
  bool _offline = false; // true = daftar event berasal dari salinan di HP
  String? _error;
  Position? _pos;

  static const Map<String, String> _sortLabels = <String, String>{
    'start': 'Soonest',
    'price_asc': 'Price: low to high',
    'price_desc': 'Price: high to low',
    'nearest': 'Nearest to me',
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

  List<Event> _parseEvents(List<dynamic> data) => data
      .map((e) => Event.fromJson(Map<String, dynamic>.from(e as Map)))
      .where((e) => !e.hasEnded) // event yang sudah selesai tidak dijual lagi
      .toList();

  /// Salinan daftar event dari HP (disimpan tiap kali daftar tanpa filter berhasil dimuat).
  /// Pencarian dan kategori dijalankan di app karena server tidak terjangkau.
  Future<bool> _loadFromCache() async {
    try {
      final raw = await LocalDb.instance.getCache(currentUserId(), 'events');
      if (raw == null) return false;
      var list = _parseEvents(jsonDecode(raw) as List);
      final q = _search.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        list = list
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.artistLabel.toLowerCase().contains(q) ||
                e.venueName.toLowerCase().contains(q))
            .toList();
      }
      if (_category != null) list = list.where((e) => e.category == _category).toList();
      if (_sort == 'price_asc') list.sort((a, b) => a.priceIdr.compareTo(b.priceIdr));
      if (_sort == 'price_desc') list.sort((a, b) => b.priceIdr.compareTo(a.priceIdr));
      if (_sort == 'start' || _sort == 'nearest') list.sort((a, b) => a.startUtc.compareTo(b.startUtc));
      if (!mounted) return true;
      setState(() {
        _events = list;
        _offline = true;
        _error = null;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.get('/api/events', query: <String, String>{
        'q': _search.text.trim(),
        'sort': _sort == 'nearest' ? 'start' : _sort, // "terdekat" diurutkan di app, berdasarkan lokasi device
        if (_category != null) 'category': _category!,
      }) as List;
      // Simpan salinan hanya dari daftar lengkap (tanpa pencarian/kategori) supaya cache tidak terpotong.
      if (_search.text.trim().isEmpty && _category == null) {
        unawaited(LocalDb.instance.putCache(currentUserId(), 'events', jsonEncode(data)).catchError((Object _) {}));
      }
      if (mounted) {
        setState(() {
          _events = _parseEvents(data);
          _offline = false;
        });
      }
    } catch (e) {
      // Hanya error jaringan (status 0) yang memakai salinan lokal.
      final usedCache = e is ApiException && e.status == 0 && await _loadFromCache();
      if (!usedCache && mounted) setState(() => _error = e.toString());
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
                SliverToBoxAdapter(child: _greeting()),
                SliverPersistentHeader(pinned: true, delegate: _PinnedControls(child: _controls())),
                ..._sections(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Bagian atas yang ikut ter-scroll: logo, sapaan.
  Widget _greeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const KonfetiLogo(size: 46),
          const SizedBox(width: 10),
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
      ]),
    );
  }

  /// Search + sort + filter kategori: di-pin di atas (tidak ikut scroll).
  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
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
                if (v == 'nearest') {
                  if (_pos == null) {
                    _loadLocation(); // minta izin/ambil lokasi; daftar otomatis terurut begitu lokasi didapat
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Getting your location… allow location access to sort by distance.')));
                  }
                  return; // data sama, urutan dihitung di app
                }
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[AppColors.glassSheen, AppColors.glass],
                  ),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(Icons.tune_rounded, color: AppColors.sun),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
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

    // Mode "Nearest to me": urut berdasarkan jarak dari device; event tanpa koordinat ditaruh paling akhir.
    final list = List<Event>.of(_events);
    if (_sort == 'nearest' && _pos != null) {
      list.sort((a, b) {
        final ka = _km(a), kb = _km(b);
        if (ka == null && kb == null) return 0;
        if (ka == null) return 1;
        if (kb == null) return -1;
        return ka.compareTo(kb);
      });
    }
    final live = list.where((e) => e.isLive).toList();
    final hero = live.isNotEmpty ? live.first : list.first;
    final nearby = list.where((e) => _km(e) != null).toList()..sort((a, b) => _km(a)!.compareTo(_km(b)!));
    final upcoming = list.where((e) => e.id != hero.id).toList();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 800 ? 4 : (width > 520 ? 3 : 2);

    return <Widget>[
      if (_offline)
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Row(children: <Widget>[
              Icon(Icons.cloud_off_outlined, size: 16, color: AppColors.sun),
              SizedBox(width: 8),
              Expanded(
                child: Text('Offline: showing events saved on this phone. Prices and stock may be outdated.',
                    style: TextStyle(color: AppColors.sky, fontSize: 12)),
              ),
            ]),
          ),
        ),
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
              childAspectRatio: 0.74,
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

/// Delegate untuk header yang menempel (pinned): latar kaca blur supaya konten yang lewat di bawahnya samar.
class _PinnedControls extends SliverPersistentHeaderDelegate {
  _PinnedControls({required this.child});
  final Widget child;

  static const double _extent = 118;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: AppColors.bg.withAlpha(overlapsContent ? 214 : 0),
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedControls oldDelegate) => true;
}

/// Lapisan teks di atas foto: transparan di atas, makin pekat ke bawah, jadi wajah artis tetap terlihat.
/// Tingginya mengikuti isi (sekitar seperempat foto).
class _PosterOverlay extends StatelessWidget {
  const _PosterOverlay({required this.padding, required this.child});
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x000A192F), Color(0xB30A192F), Color(0xE60A192F)],
          stops: <double>[0, 0.55, 1],
        ),
      ),
      child: child,
    );
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
          height: 350,
          child: Stack(fit: StackFit.expand, children: <Widget>[
            EventBanner(event: event, heroTag: 'hero-${event.id}'),
            Positioned(
              left: 12,
              top: 12,
              child: Tag(live ? 'LIVE NOW' : 'FEATURED',
                  icon: live ? Icons.circle : Icons.star_rounded, color: live ? AppColors.danger : AppColors.butter),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PosterOverlay(
                padding: const EdgeInsets.fromLTRB(16, 36, 14, 14),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(event.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(size: 21, height: 1.15)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                        Text('${event.artistLabel} • ${p.date}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.sky, fontSize: 12)),
                        const SizedBox(height: 3),
                        Text('From ${rupiah(event.priceIdr)}',
                            style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w800, fontSize: 16)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: const BoxDecoration(color: AppColors.sun, borderRadius: BorderRadius.all(Radius.circular(999))),
                      child: Text(event.soldOut ? 'Sold out' : 'Get Tickets',
                          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ]),
                ]),
              ),
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
        child: Stack(fit: StackFit.expand, children: <Widget>[
          EventBanner(event: event, heroTag: 'near-${event.id}'),
          Positioned(
              left: 8,
              top: 8,
              child: GlassChip('${km.toStringAsFixed(km < 10 ? 1 : 0)} km', icon: Icons.near_me, iconColor: AppColors.sun)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _PosterOverlay(
              padding: const EdgeInsets.fromLTRB(12, 26, 12, 11),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 3),
                Row(children: <Widget>[
                  Expanded(
                    child: Text(event.venueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  Text(rupiah(event.priceIdr), style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
              ]),
            ),
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
      child: Stack(fit: StackFit.expand, children: <Widget>[
        EventBanner(event: event, heroTag: 'grid-${event.id}'),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _PosterOverlay(
            padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 3),
              Row(children: <Widget>[
                Expanded(
                  child: Text('${p.day} ${p.month}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 11)),
                ),
                const SizedBox(width: 4),
                Text(rupiah(event.priceIdr), style: const TextStyle(color: AppColors.sun, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
