import '../core/config.dart';

class Event {
  Event({
    required this.id,
    required this.title,
    required this.artist,
    required this.category,
    required this.venueName,
    required this.latitude,
    required this.longitude,
    required this.isOutdoor,
    required this.startUtc,
    required this.endUtc,
    required this.priceIdr,
    required this.stock,
    this.spotifyArtistId,
    this.imageUrl,
    this.lineup = const <String>[],
  });

  final int id;
  final String title;
  final String artist;
  final String category;
  final String venueName;
  final double? latitude;
  final double? longitude;
  final bool isOutdoor;
  final DateTime startUtc;
  final DateTime endUtc;
  final int priceIdr;
  final int stock;
  final String? spotifyArtistId;
  final String? imageUrl;

  /// Semua artis yang tampil. Jika backend tidak mengirim lineup, berisi headliner saja.
  final List<String> lineup;

  List<String> get artists => lineup.isEmpty ? <String>[artist] : lineup;
  bool get isMultiArtist => artists.length > 1;
  String get artistLabel => artists.join(', ');

  bool get isLive {
    final now = DateTime.now().toUtc();
    return now.isAfter(startUtc) && now.isBefore(endUtc);
  }

  bool get hasEnded => endUtc.isBefore(DateTime.now());
  bool get soldOut => stock <= 0;

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: (j['id'] as num).toInt(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        category: (j['category'] ?? '') as String,
        venueName: (j['venue_name'] ?? '') as String,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        isOutdoor: (j['is_outdoor'] as num?)?.toInt() == 1,
        startUtc: DateTime.parse(j['start_time_utc'] as String).toUtc(),
        endUtc: DateTime.parse(j['end_time_utc'] as String).toUtc(),
        priceIdr: (j['price_idr'] as num).toInt(),
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        spotifyArtistId: j['spotify_artist_id'] as String?,
        imageUrl: j['image_url'] as String?,
        lineup: ((j['lineup'] ?? '') as String)
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
}

/// Baris dari GET /api/orders
class Order {
  Order({
    required this.orderId,
    required this.eventId,
    required this.qty,
    required this.grossAmount,
    required this.status,
    required this.title,
    required this.artist,
    required this.venueName,
    required this.startUtc,
    required this.createdAt,
    this.snapToken,
    this.redirectUrl,
  });

  final String orderId;
  final int eventId;
  final int qty;
  final int grossAmount;
  final String status; // pending | paid | expired | failed
  final String title;
  final String artist;
  final String venueName;
  final DateTime startUtc;
  final String createdAt;
  final String? snapToken;
  final String? redirectUrl;

  /// Tanpa snap token = order demo (Midtrans key kosong) -> dibayar lewat endpoint simulate.
  bool get isDemo => snapToken == null || snapToken!.isEmpty;

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        orderId: j['order_id'] as String,
        eventId: (j['event_id'] as num).toInt(),
        qty: (j['qty'] as num).toInt(),
        grossAmount: (j['gross_amount'] as num).toInt(),
        status: (j['status'] ?? 'pending') as String,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        venueName: (j['venue_name'] ?? '') as String,
        startUtc: DateTime.parse(j['start_time_utc'] as String).toUtc(),
        createdAt: (j['created_at'] ?? '') as String,
        snapToken: j['snap_token'] as String?,
        redirectUrl: j['redirect_url'] as String?,
      );
}

/// Baris dari GET /api/tickets
class Ticket {
  Ticket({
    required this.code,
    required this.orderId,
    required this.eventId,
    required this.title,
    required this.artist,
    required this.venueName,
    required this.startUtc,
    required this.endUtc,
    required this.isOutdoor,
    required this.state,
    this.latitude,
    this.longitude,
  });

  final String code;
  final String orderId;
  final int eventId;
  final String title;
  final String artist;
  final String venueName;
  final DateTime startUtc;
  final DateTime endUtc;
  final bool isOutdoor;
  final String state; // active | history (ditentukan server)
  final double? latitude;
  final double? longitude;

  bool get isLive {
    final now = DateTime.now().toUtc();
    return now.isAfter(startUtc) && now.isBefore(endUtc);
  }

  /// Detail tiket (QR, syarat masuk, tombol darurat) hanya dibuka saat event berlangsung.
  bool get canOpenDetail {
    if (AppConfig.demoUnlockTickets) return true;
    final now = DateTime.now().toUtc();
    return now.isAfter(startUtc.subtract(AppConfig.earlyAccess)) && now.isBefore(endUtc);
  }

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        code: j['ticket_code'] as String,
        orderId: j['order_id'] as String,
        eventId: (j['event_id'] as num).toInt(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        venueName: (j['venue_name'] ?? '') as String,
        startUtc: DateTime.parse(j['start_time_utc'] as String).toUtc(),
        endUtc: DateTime.parse(j['end_time_utc'] as String).toUtc(),
        isOutdoor: (j['is_outdoor'] as num?)?.toInt() == 1,
        state: (j['state'] ?? 'active') as String,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}

/// Tiket dalam satu pemesanan (order). Di list tampil 1 kartu; di detail tampil semua tiketnya.
class TicketGroup {
  TicketGroup(this.tickets);
  final List<Ticket> tickets;

  Ticket get first => tickets.first;
  int get count => tickets.length;
  String get orderId => first.orderId;
  int get eventId => first.eventId;
  String get title => first.title;
  String get artist => first.artist;
  String get venueName => first.venueName;
  DateTime get startUtc => first.startUtc;
  DateTime get endUtc => first.endUtc;
  bool get isLive => first.isLive;
  bool get canOpenDetail => first.canOpenDetail;
}

List<TicketGroup> groupTickets(List<Ticket> tickets) {
  final byOrder = <String, List<Ticket>>{};
  for (final t in tickets) {
    byOrder.putIfAbsent(t.orderId, () => <Ticket>[]).add(t);
  }
  return byOrder.values.map(TicketGroup.new).toList();
}
