import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../models/event.dart';

/// Fasilitas di area venue. Posisinya DEMO: offset tetap dari koordinat venue (0.0001° ≈ 11 m),
/// karena database belum punya denah per venue. Ganti offset dengan koordinat asli bila tersedia.
enum VenueFacility {
  stage('Main stage', Icons.mic, AppColors.sun, 0.00022, 0.00000),
  toilet('Toilets', Icons.wc, Color(0xFF3FA3DC), -0.00018, 0.00028),
  medical('Medical post', Icons.local_hospital, Color(0xFFFF6B6B), 0.00008, -0.00030),
  exit('Exit gate', Icons.exit_to_app, Color(0xFF2ECC71), -0.00028, -0.00012);

  const VenueFacility(this.label, this.icon, this.color, this.dLat, this.dLng);
  final String label;
  final IconData icon;
  final Color color;
  final double dLat;
  final double dLng;
}

/// Lokasi pengguna. Dengan request=false tidak memunculkan dialog izin (hanya memakai izin yang sudah ada).
Future<LatLng?> _findMe({required bool request}) async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied && request) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 6)),
        );
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null; // GPS mati / timeout / izin ditolak
  }
}

String _distanceText(LatLng a, LatLng b) {
  final m = Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
  return m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
}

Future<void> _navigateTo(Event e) async {
  if (e.latitude == null || e.longitude == null) return;
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${e.latitude},${e.longitude}');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {/* tidak ada aplikasi peta/browser */}
}

/// Peta OpenStreetMap: pin venue, fasilitas, dan posisi pengguna.
class VenueMap extends StatelessWidget {
  const VenueMap({
    super.key,
    required this.venue,
    this.me,
    this.visible,
    this.interactive = true,
    this.controller,
  });

  final LatLng venue;
  final LatLng? me;

  /// Fasilitas yang ditampilkan (null = semua).
  final Set<VenueFacility>? visible;
  final bool interactive;
  final MapController? controller;

  Widget _dot(IconData icon, Color color) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, size: 18, color: color == AppColors.sun ? AppColors.ink : Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    final shown = visible ?? VenueFacility.values.toSet();
    final myPoint = me;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: venue,
        initialZoom: 17,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
              : InteractiveFlag.none,
        ),
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.code_konfeti',
        ),
        MarkerLayer(markers: <Marker>[
          for (final f in VenueFacility.values)
            if (shown.contains(f))
              Marker(
                point: LatLng(venue.latitude + f.dLat, venue.longitude + f.dLng),
                width: 34,
                height: 34,
                child: Tooltip(message: f.label, triggerMode: TooltipTriggerMode.tap, child: _dot(f.icon, f.color)),
              ),
          Marker(
            point: venue,
            width: 44,
            height: 44,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.location_on, size: 44, color: Color(0xFFE53935)),
          ),
          if (myPoint != null)
            Marker(
              point: myPoint,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2F80ED),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
        ]),
        // atribusi wajib OpenStreetMap
        const Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xB3FFFFFF)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 9.5, color: Colors.black87)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pratinjau peta di halaman detail event. Ketuk untuk membuka peta penuh (agar tidak bentrok dengan scroll halaman).
class VenueMapPreview extends StatefulWidget {
  const VenueMapPreview({super.key, required this.event});
  final Event event;

  @override
  State<VenueMapPreview> createState() => _VenueMapPreviewState();
}

class _VenueMapPreviewState extends State<VenueMapPreview> {
  LatLng? _me;

  bool get _hasCoords => widget.event.latitude != null && widget.event.longitude != null;
  LatLng get _venue => LatLng(widget.event.latitude!, widget.event.longitude!);

  @override
  void initState() {
    super.initState();
    if (_hasCoords) _locate();
  }

  Future<void> _locate() async {
    final me = await _findMe(request: false);
    if (mounted && me != null) setState(() => _me = me);
  }

  void _openFull() {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VenueMapPage(event: widget.event)));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    if (!_hasCoords) {
      return AppCard(
        child: Row(children: <Widget>[
          const Icon(Icons.place, color: AppColors.sun),
          const SizedBox(width: 10),
          Expanded(child: Text(e.venueName, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
    }
    final me = _me;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(
          height: 190,
          width: double.infinity,
          child: Stack(children: <Widget>[
            Positioned.fill(child: IgnorePointer(child: VenueMap(venue: _venue, me: me, interactive: false))),
            Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: _openFull))),
            const Positioned(left: 10, top: 10, child: Tag('Tap to explore', icon: Icons.touch_app_outlined)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(e.venueName, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (me != null)
                  Text('${_distanceText(me, _venue)} from you', style: const TextStyle(color: AppColors.sky, fontSize: 12)),
              ]),
            ),
            FilledButton.icon(
              onPressed: () => _navigateTo(e),
              icon: const Icon(Icons.directions_outlined, size: 18),
              label: const Text('Navigate'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Peta layar penuh: geser/zoom, filter fasilitas, posisi saya, jarak ke venue, dan navigasi.
class VenueMapPage extends StatefulWidget {
  const VenueMapPage({super.key, required this.event});
  final Event event;

  @override
  State<VenueMapPage> createState() => _VenueMapPageState();
}

class _VenueMapPageState extends State<VenueMapPage> {
  final MapController _controller = MapController();
  final Set<VenueFacility> _visible = VenueFacility.values.toSet();
  LatLng? _me;

  LatLng get _venue => LatLng(widget.event.latitude!, widget.event.longitude!);

  @override
  void initState() {
    super.initState();
    _locate(request: false);
  }

  Future<void> _locate({required bool request, bool recenter = false}) async {
    final me = await _findMe(request: request);
    if (!mounted) return;
    if (me == null) {
      if (request) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on location and allow the permission to see where you are.')),
        );
      }
      return;
    }
    setState(() => _me = me);
    if (recenter) _controller.move(me, 16);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: Text(e.venueName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: const <Widget>[RotateButton()],
      ),
      body: Column(children: <Widget>[
        Expanded(
          child: Stack(children: <Widget>[
            Positioned.fill(child: VenueMap(venue: _venue, me: me, visible: _visible, controller: _controller)),
            Positioned(
              left: 0,
              right: 0,
              top: 10,
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: <Widget>[
                    for (final f in VenueFacility.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: DecoratedBox(
                          decoration: const ShapeDecoration(color: AppColors.bg, shape: StadiumBorder()),
                          child: CategoryPill(
                            label: f.label,
                            icon: f.icon,
                            selected: _visible.contains(f),
                            onTap: () => setState(() {
                              if (!_visible.remove(f)) _visible.add(f);
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.bgAlt,
            border: Border(top: BorderSide(color: AppColors.skyFaint)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(e.venueName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                  me == null ? 'Tap "Locate me" to see how far you are.' : '${_distanceText(me, _venue)} from your location',
                  style: const TextStyle(color: AppColors.sky, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _controller.move(_venue, 17),
                      icon: const Icon(Icons.location_on_outlined, size: 16),
                      label: const Text('Venue'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _locate(request: true, recenter: true),
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('Locate me'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _navigateTo(e),
                      icon: const Icon(Icons.directions_outlined, size: 16),
                      label: const Text('Navigate'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text(
                  'Facility positions are a demo layout around the venue.',
                  style: TextStyle(color: AppColors.skyDim, fontSize: 11),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
