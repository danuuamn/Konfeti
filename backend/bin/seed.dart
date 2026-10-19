import 'dart:io';

import 'package:konfeti_backend/src/db.dart';
import 'package:konfeti_backend/src/env.dart';
import 'package:konfeti_backend/src/routes/spotify.dart' show fetchArtistImage;
import 'package:konfeti_backend/src/util.dart';

String _addDays(double days) {
  final ms = (days * 24 * 3600 * 1000).round();
  return isoMs(DateTime.now().add(Duration(milliseconds: ms)));
}

// Semua event di bawah adalah DATA DUMMY untuk tugas kuliah (nama artis nyata dipakai agar Spotify API
// dapat menemukan datanya). Venue, tanggal, dan harga hanya rekaan.
List<List<Object?>> _events() => <List<Object?>>[
      // [title, artist, category, venue, lat, lng, outdoor, start, end, price, stock]
      ['Hindia Live Session', 'Hindia', 'Indie', 'Lapangan UPN Veteran Yogyakarta', -7.7618, 110.4087, 1, _addDays(3), _addDays(3.15), 150000, 200],
      ['Denny Caknan Koplo Night', 'Denny Caknan', 'Dangdut', 'Alun-Alun Kidul, Yogyakarta', -7.8118, 110.3638, 1, _addDays(5), _addDays(5.2), 75000, 500],
      ['Raisa Intimate Concert', 'Raisa', 'Pop', 'Taman Budaya Yogyakarta', -7.8008, 110.3686, 0, _addDays(9), _addDays(9.12), 300000, 120],
      ['Tulus Live in Yogyakarta', 'Tulus', 'Pop', 'Jogja Expo Center', -7.7981, 110.4086, 0, _addDays(12), _addDays(12.15), 450000, 300],
      ['Sheila On 7 Reunion Night', 'Sheila On 7', 'Rock', 'Stadion Maguwoharjo, Sleman', -7.7506, 110.4147, 1, _addDays(20), _addDays(20.2), 350000, 400],
      ['Isyana Live in Jayapura', 'Isyana Sarasvati', 'Pop', 'Stadion Mandala, Jayapura', -2.5337, 140.7181, 1, _addDays(25), _addDays(25.15), 250000, 250],
      ['Dewa 19 Pesta Rock', 'Dewa 19', 'Rock', 'Stadion Mandala Krida, Yogyakarta', -7.7960, 110.3811, 1, _addDays(30), _addDays(30.2), 400000, 350],
      ['Bruno Mars Live', 'Bruno Mars', 'Pop', 'Jakarta International Stadium', -6.1264, 106.8325, 1, _addDays(45), _addDays(45.2), 1500000, 800],
      ['Dua Lipa Live in Bali', 'Dua Lipa', 'Pop', 'GWK Cultural Park, Bali', -8.8106, 115.1676, 1, _addDays(60), _addDays(60.2), 1200000, 600],
      ['Coldplay Live in Concert', 'Coldplay', 'Rock', 'Gelora Bung Karno Stadium, Jakarta', -6.2186, 106.8019, 1, _addDays(75), _addDays(75.2), 1800000, 1000],
      // Event yang sudah selesai (untuk tes status "history")
      ['Nadin Amizah Retro Night', 'Nadin Amizah', 'Indie', 'Concert Hall TBY, Yogyakarta', -7.8008, 110.3686, 0, _addDays(-10), _addDays(-9.9), 200000, 100],
    ];


// Kategori tiket per artis: [nama, deskripsi, harga IDR, stok].
// Artis besar punya banyak kategori (mengikuti pola konser nyata: tribun CAT bernomor, Festival/standing, VIP),
// artis yang kurang terkenal hanya 1 kategori. Harga & stok adalah DATA DUMMY perkiraan untuk tugas kuliah.
const List<List<Object?>> _singleTier = <List<Object?>>[
  <Object?>['Regular', 'General admission (open seating)'],
];

const Map<String, List<List<Object?>>> _tiers = <String, List<List<Object?>>>{
  'Coldplay': <List<Object?>>[
    <Object?>['CAT 6', 'Upper tribune, farthest from the stage', 900000, 150],
    <Object?>['CAT 5', 'Upper tribune, side view', 1300000, 150],
    <Object?>['CAT 4', 'Lower tribune, side view', 1800000, 150],
    <Object?>['CAT 3', 'Lower tribune, wide view', 2400000, 120],
    <Object?>['CAT 2', 'Lower tribune, near the stage', 3200000, 100],
    <Object?>['CAT 1', 'Lower tribune, front-centre view', 4000000, 80],
    <Object?>['Festival', 'Standing zone on the pitch', 3500000, 200],
    <Object?>['VIP Pit', 'Front standing pit, closest to the stage', 6500000, 50],
  ],
  'Bruno Mars': <List<Object?>>[
    <Object?>['CAT 3', 'Upper tribune', 1000000, 200],
    <Object?>['CAT 2', 'Lower tribune, side view', 1500000, 180],
    <Object?>['CAT 1', 'Lower tribune, front-centre view', 2200000, 140],
    <Object?>['Festival', 'Standing zone on the pitch', 2800000, 200],
    <Object?>['VIP', 'Front pit and fast-lane entrance', 5500000, 80],
  ],
  'Dua Lipa': <List<Object?>>[
    <Object?>['General Standing', 'Standing zone at the back', 1200000, 200],
    <Object?>['CAT 2', 'Elevated side seating', 1800000, 150],
    <Object?>['CAT 1', 'Front-centre seating', 2600000, 120],
    <Object?>['Golden Circle', 'Standing zone right at the stage', 4500000, 80],
    <Object?>['VIP Lounge', 'Seating with lounge access', 6000000, 50],
  ],
  'Dewa 19': <List<Object?>>[
    <Object?>['Tribun Selatan', 'South stand, open seating', 400000, 100],
    <Object?>['Tribun Utara', 'North stand, open seating', 550000, 80],
    <Object?>['Tribun Barat', 'West stand, main-view seating', 750000, 70],
    <Object?>['Festival', 'Standing zone in front of the stage', 900000, 80],
    <Object?>['VIP', 'Front seating with fast lane', 1500000, 20],
  ],
  'Sheila On 7': <List<Object?>>[
    <Object?>['Tribun', 'Open seating tribune', 350000, 130],
    <Object?>['Tribun Premium', 'Main-view seating', 550000, 110],
    <Object?>['Festival', 'Standing zone in front of the stage', 700000, 120],
    <Object?>['VIP', 'Front seating with fast lane', 1200000, 40],
  ],
  'Tulus': <List<Object?>>[
    <Object?>['CAT 3', 'Back rows', 450000, 100],
    <Object?>['CAT 2', 'Middle rows', 700000, 100],
    <Object?>['CAT 1', 'Front rows', 1000000, 70],
    <Object?>['VIP', 'First rows, centre', 1800000, 30],
  ],
  'Raisa': <List<Object?>>[
    <Object?>['Balcony', 'Upper level', 300000, 40],
    <Object?>['Regular', 'Main floor seating', 500000, 60],
    <Object?>['VIP', 'Front rows, centre', 850000, 20],
  ],
  'Isyana Sarasvati': <List<Object?>>[
    <Object?>['Regular', 'Open seating', 250000, 130],
    <Object?>['Premium', 'Main-view seating', 450000, 90],
    <Object?>['VIP', 'Front seating', 800000, 30],
  ],
};

// (Opsional) isi alamat gambar sendiri, mis. 'Tulus': 'https://.../tulus.jpg' atau
// '/uploads/artists/tulus.jpg' (taruh file di backend/uploads/artists/). Yang kosong diambil dari Spotify.
const Map<String, String> _manualImages = <String, String>{};

const List<List<Object?>> _promos = <List<Object?>>[
  ['KONFETI10', 'Welcome promo: 10% off your tickets', 10],
  ['STUDENT20', 'Student discount: 20% off', 20],
  ['WEEKEND15', 'Weekend special: 15% off', 15],
];

Future<void> main(List<String> args) async {
  Env.load();
  final db = await AppDb.open();

  if (args.contains('--reset')) {
    // hapus data yang bergantung pada events (urutan penting karena foreign key)
    for (final t in <String>[
      'emergency_alerts',
      'blocks',
      'tickets',
      'transactions',
      'notifications',
      'ticket_tiers',
      'events',
    ]) {
      await db.run('DELETE FROM $t');
    }
    print('Events, orders, tickets, blocks, and notifications cleared (users are kept).');
  }

  for (final p in _promos) {
    await db.run('INSERT INTO promos(code,description,discount_percent) VALUES(?,?,?) ON CONFLICT DO NOTHING', p);
  }

  List<List<Object?>> tiersFor(String artist, int price, int stock) {
    final t = _tiers[artist];
    if (t != null) return t;
    return <List<Object?>>[
      <Object?>[_singleTier.first[0], _singleTier.first[1], price, stock],
    ];
  }

  Future<void> insertTiers(AppDb d, int eventId, List<List<Object?>> tiers) async {
    var order = 0;
    for (final t in tiers) {
      await d.run(
        'INSERT INTO ticket_tiers(event_id,name,description,price_idr,stock,sort_order) VALUES(?,?,?,?,?,?)',
        <Object?>[eventId, t[0], t[1], t[2], t[3], order++],
      );
    }
  }

  int minPrice(List<List<Object?>> tiers) => tiers.map((t) => t[2] as int).reduce((a, b) => a < b ? a : b);
  int sumStock(List<List<Object?>> tiers) => tiers.fold<int>(0, (a, t) => a + (t[3] as int));

  final count = (await db.one('SELECT COUNT(*) AS n FROM events'))!['n'] as int;
  if (count == 0) {
    final events = _events();
    await db.transaction<void>((tx) async {
      for (final e in events) {
        final tiers = tiersFor(e[1] as String, e[9] as int, e[10] as int);
        final row = List<Object?>.from(e);
        row[9] = minPrice(tiers); // harga "mulai dari"
        row[10] = sumStock(tiers); // total stok semua kategori
        final id = await tx.insert(
              '''INSERT INTO events(title,artist,category,venue_name,latitude,longitude,is_outdoor,
                      start_time_utc,end_time_utc,price_idr,stock)
   VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
              row,
            );
        await insertTiers(tx, id, tiers);
      }
    });
    print('Seeded ${events.length} events (with ticket categories) and ${_promos.length} promo codes.');
  } else {
    // Database lama: lengkapi kategori tiket untuk event yang belum punya.
    var filled = 0;
    final rows = await db.all('SELECT id, artist, price_idr, stock FROM events');
    await db.transaction<void>((tx) async {
      for (final ev in rows) {
        final has = (await tx.one('SELECT COUNT(*) AS n FROM ticket_tiers WHERE event_id=?', <Object?>[ev['id']]))!['n'] as int;
        if (has > 0) continue;
        final tiers = tiersFor(ev['artist'] as String? ?? '', ev['price_idr'] as int, ev['stock'] as int);
        await insertTiers(tx, ev['id'] as int, tiers);
        final sold = (await tx.one('SELECT COUNT(*) AS n FROM tickets WHERE event_id=?', <Object?>[ev['id']]))!['n'] as int;
        final left = sumStock(tiers) - sold;
        await tx.run('UPDATE events SET price_idr=?, stock=? WHERE id=?', <Object?>[minPrice(tiers), left < 0 ? 0 : left, ev['id']]);
        filled++;
      }
    });
    print('Events table already has $count rows. Ticket categories added to $filled event(s). '
        'Use "dart run bin/seed.dart --reset" to reseed everything.');
  }

  // Gambar artis: alamat manual dulu, kalau tidak ada diambil dari Spotify (butuh key di .env).
  final refresh = args.contains('--images') || args.contains('--reset');
  final events = await db.all('SELECT id, artist, image_url FROM events');
  final cache = <String, String?>{};
  var withImage = 0;
  for (final ev in events) {
    final artist = ev['artist'] as String? ?? '';
    final current = ev['image_url'];
    if (artist.isEmpty) continue;
    if (current is String && current.isNotEmpty && !refresh) {
      withImage++;
      continue;
    }
    if (!cache.containsKey(artist)) {
      cache[artist] = _manualImages[artist] ?? await fetchArtistImage(artist);
    }
    final url = cache[artist];
    if (url != null) {
      await db.run('UPDATE events SET image_url=? WHERE id=?', <Object?>[url, ev['id']]);
      withImage++;
    }
  }
  print('Artist images: $withImage of ${events.length} events have an image'
      '${withImage < events.length ? ' (set SPOTIFY_CLIENT_ID/SECRET in .env, then run "dart run bin/seed.dart --images")' : ''}.');
  exit(0);
}