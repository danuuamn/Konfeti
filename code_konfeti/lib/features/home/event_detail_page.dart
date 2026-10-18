import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/favorites.dart';
import '../../core/formatters.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';
import '../../services/sensor_service.dart';
import '../../services/time_zones.dart';
import '../checkout/checkout_page.dart';
import '../tickets/artist_section.dart';
import 'event_banner.dart';
import 'event_times_card.dart';
import 'venue_map_preview.dart';
import 'weather_card.dart';

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({super.key, required this.event});
  final Event event;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Event _event = widget.event;
  String? _artist; // artis yang dipilih di lineup

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Ambil stok terbaru dari server.
  Future<void> _refresh() async {
    try {
      final j = await ApiClient.instance.get('/api/events/${widget.event.id}') as Map;
      if (mounted) setState(() => _event = Event.fromJson(Map<String, dynamic>.from(j)));
    } catch (_) {/* pakai data yang sudah ada */}
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    final canBuy = !e.soldOut && !e.hasEnded;
    final selected = e.artists.contains(_artist) ? _artist! : e.artists.first;

    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: <Widget>[
        _hero(e),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(e.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              Tag(e.category),
              Tag(e.isOutdoor ? 'Outdoor' : 'Indoor', outlined: true),
              if (e.isLive) const Tag('LIVE NOW', icon: Icons.circle),
            ]),
            const SizedBox(height: 14),
            _infoRow(Icons.place, e.venueName),
            _infoRow(Icons.event, () {
              final p = zoneParts(e.startUtc, 'Asia/Jakarta');
              return '${p.date} • ${p.time} ${p.abbr}';
            }()),
            _infoRow(Icons.confirmation_number_outlined, e.soldOut ? 'Sold out' : '${e.stock} tickets left'),
            const SizedBox(height: 16),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('About this event', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  '${e.isMultiArtist ? 'Featuring ${e.artistLabel}' : e.artist} live at ${e.venueName}. '
                  'An ${e.isOutdoor ? 'outdoor' : 'indoor'} ${e.category.toLowerCase()} show. Grab your tickets before they run out!',
                  style: const TextStyle(color: AppColors.sky, height: 1.5),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            EventTimesCard(startUtc: e.startUtc),

            // ---- Lineup + profil Spotify (mendukung 1 atau lebih artis) ----
            SectionHeader(e.isMultiArtist ? 'Lineup • ${e.artists.length} artists' : 'Artist',
                padding: const EdgeInsets.fromLTRB(0, 22, 0, 10)),
            if (e.isMultiArtist) ...<Widget>[
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: e.artists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => CategoryPill(
                    label: e.artists[i],
                    icon: i == 0 ? Icons.star_rounded : null,
                    selected: e.artists[i] == selected,
                    onTap: () => setState(() => _artist = e.artists[i]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text('Tap an artist to see their top tracks.', style: TextStyle(color: AppColors.sky, fontSize: 12)),
              const SizedBox(height: 10),
            ],
            // key = nama artis, jadi widget dibuat ulang (dan pemutar audio dihentikan) saat ganti artis
            ArtistSection(key: ValueKey<String>(selected), artist: selected),

            const SectionHeader('Venue Location', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            VenueMapPreview(event: e),

            // Prakiraan cuaca (OpenWeatherMap) hanya untuk event outdoor
            if (e.isOutdoor && e.latitude != null && e.longitude != null) ...<Widget>[
              const SectionHeader('Weather at the Venue', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
              WeatherCard(key: ValueKey<int>(e.id), event: e),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgAlt,
          border: Border(top: BorderSide(color: AppColors.skyFaint)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: <Widget>[
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Text('Start from', style: TextStyle(color: AppColors.sky, fontSize: 12)),
                Text(rupiah(e.priceIdr), style: const TextStyle(color: AppColors.sun, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: canBuy
                      ? () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CheckoutPage(event: e)))
                      : null,
                  child: Text(e.hasEnded ? 'Event ended' : (e.soldOut ? 'Sold out' : 'Buy Ticket')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _hero(Event e) {
    return Stack(children: <Widget>[
      EventBanner(event: e, height: 300),
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x66000000), Color(0x00000000), AppColors.bg],
              stops: <double>[0, 0.5, 1],
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
              CircleIconButton(icon: Icons.arrow_back, tooltip: 'Back', onTap: () => Navigator.pop(context)),
              Row(children: <Widget>[
                CircleIconButton(
                    icon: Icons.screen_rotation, tooltip: 'Rotate screen', onTap: SensorService.instance.toggleOrientation),
                const SizedBox(width: 8),
                ValueListenableBuilder<Set<int>>(
                  valueListenable: Favorites.ids,
                  builder: (_, ids, __) {
                    final fav = ids.contains(e.id);
                    return CircleIconButton(
                      icon: fav ? Icons.favorite : Icons.favorite_border,
                      color: fav ? AppColors.sun : Colors.white,
                      tooltip: 'Favorite',
                      onTap: () => Favorites.toggle(e.id),
                    );
                  },
                ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: <Widget>[
          Icon(icon, size: 18, color: AppColors.sun),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ]),
      );
}
