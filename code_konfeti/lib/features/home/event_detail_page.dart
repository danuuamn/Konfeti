import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../models/event.dart';
import '../checkout/checkout_page.dart';
import 'event_times_card.dart';
import 'home_page.dart';

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({super.key, required this.event});
  final Event event;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Event _event = widget.event;

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
    final theme = Theme.of(context);
    final e = _event;
    final canBuy = !e.soldOut && !e.hasEnded;
    return Scaffold(
      appBar: AppBar(title: Text(e.artist)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: <Widget>[
        EventBanner(event: e, height: 180),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(e.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: <Widget>[
              Chip(label: Text(e.category)),
              Chip(label: Text(e.isOutdoor ? 'Outdoor' : 'Indoor')),
            ]),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              const Icon(Icons.place_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(e.venueName)),
            ]),
            const SizedBox(height: 12),
            EventTimesCard(startUtc: e.startUtc),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
              Text(rupiah(e.priceIdr),
                  style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary)),
              Text(e.soldOut ? 'Sold out' : '${e.stock} tickets left'),
            ]),
            // TODO(Danu): letakkan widget cuaca (OpenWeatherMap) & peta venue (LBS) di sini.
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: canBuy
                ? () => Navigator.push(
                    context, MaterialPageRoute<void>(builder: (_) => CheckoutPage(event: e)))
                : null,
            child: Text(e.hasEnded ? 'Event ended' : (e.soldOut ? 'Sold out' : 'Buy ticket')),
          ),
        ),
      ),
    );
  }
}
