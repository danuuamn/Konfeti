import 'dart:ui' show ImageFilter;

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

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({super.key, required this.event, this.heroTag});
  final Event event;

  /// Tag Hero dari kartu asal (opsional) agar foto beranimasi ke halaman ini.
  final String? heroTag;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Event _event = widget.event;
  String? _artist; // artis yang dipilih di lineup
  int? _tierId; // kategori tiket yang dipilih (null = otomatis kategori pertama yang masih tersedia)

  /// Kategori terpilih; jika belum ada pilihan, ambil yang pertama masih tersedia.
  TicketTier? get _tier {
    final tiers = _event.tiers;
    if (tiers.isEmpty) return null;
    for (final t in tiers) {
      if (t.id == _tierId && !t.soldOut) return t;
    }
    for (final t in tiers) {
      if (!t.soldOut) return t;
    }
    return tiers.first;
  }

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
    final tier = _tier;
    final canBuy = !e.soldOut && !e.hasEnded && (tier == null || !tier.soldOut);
    final price = tier?.priceIdr ?? e.priceIdr;
    final selected = e.artists.contains(_artist) ? _artist! : e.artists.first;
    final p = zoneParts(e.startUtc, 'Asia/Jakarta');

    return Scaffold(
      extendBody: true,
      body: ListView(padding: EdgeInsets.zero, children: <Widget>[
        _hero(e),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.viewPaddingOf(context).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Expanded(child: _InfoChip(icon: Icons.event, label: 'Date', value: p.date)),
                const SizedBox(width: 10),
                Expanded(child: _InfoChip(icon: Icons.schedule, label: 'Time', value: '${p.time} ${p.abbr}')),
              ]),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Expanded(child: _InfoChip(icon: Icons.place, label: 'Venue', value: e.venueName)),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoChip(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Tickets',
                    value: e.soldOut ? 'Sold out' : '${e.stock} left',
                  ),
                ),
              ]),
            ),
            if (e.tiers.isNotEmpty) ...<Widget>[
              const SectionHeader('Choose category', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
              for (final t in e.tiers) ...<Widget>[
                _TierTile(
                  tier: t,
                  selected: t.id == tier?.id,
                  onTap: t.soldOut ? null : () => setState(() => _tierId = t.id),
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 6),
            GlassCard(
              blur: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const Text('About this event', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 12)),
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

            const SectionHeader('Venue Location', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
            VenueMapPreview(event: e),
            // TODO(Danu): widget cuaca (OpenWeatherMap) bisa diletakkan di sini.
          ]),
        ),
      ]),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.glassHigh,
              border: Border(top: BorderSide(color: AppColors.glassBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Row(children: <Widget>[
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text(tier == null ? 'Start from' : tier.name,
                        style: const TextStyle(color: AppColors.sky, fontSize: 12)),
                    Text(rupiah(price), style: const TextStyle(color: AppColors.sun, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: canBuy
                          ? () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CheckoutPage(event: e, tier: tier)))
                          : null,
                      child: Text(e.hasEnded ? 'Event ended' : (e.soldOut ? 'Sold out' : 'Buy Ticket')),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(Event e) {
    return Stack(children: <Widget>[
      EventBanner(event: e, height: 340, heroTag: widget.heroTag),
      const Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x66000000), Color(0x00000000), AppColors.bg],
                stops: <double>[0, 0.45, 1],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
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
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              Tag(e.category),
              Tag(e.isOutdoor ? 'Outdoor' : 'Indoor', outlined: true),
              if (e.isLive) const Tag('LIVE NOW', icon: Icons.circle, color: AppColors.danger),
            ]),
            const SizedBox(height: 10),
            Text(e.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.display(size: 30, height: 1.15)),
          ]),
        ),
      ),
    ]);
  }
}

/// Chip info kecil: ikon kuning + label + nilai.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(12),
      child: Row(children: <Widget>[
        Icon(icon, size: 20, color: AppColors.sun),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(label, style: const TextStyle(color: AppColors.sky, fontSize: 11)),
            const SizedBox(height: 1),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}


/// Satu baris pilihan kategori tiket (CAT 1, CAT 2, ...). Terpilih = border sorot + radio kuning.
class _TierTile extends StatelessWidget {
  const _TierTile({required this.tier, required this.selected, required this.onTap});
  final TicketTier tier;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final off = tier.soldOut;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: GlassCard(
        onTap: onTap,
        highlight: selected,
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: <Widget>[
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? AppColors.sun : AppColors.skyDim, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tier.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              if (tier.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(tier.description,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              ],
              const SizedBox(height: 4),
              Text(off ? 'Sold out' : '${tier.stock} left',
                  style: TextStyle(color: off ? AppColors.danger : AppColors.skyDim, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(rupiah(tier.priceIdr), style: const TextStyle(color: AppColors.sun, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
