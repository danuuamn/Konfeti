
import 'package:konfeti_backend/src/db.dart';
import 'package:konfeti_backend/src/env.dart';
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

// Event demo dengan LINEUP lebih dari 1 artis. Kolom `artist` = headliner (dipakai kuis Spotify),
// kolom `lineup` = semua artis dipisah koma.
List<List<Object?>> _lineupEvents() => <List<Object?>>[
      // [title, artist, lineup, category, venue, lat, lng, outdoor, start, end, price, stock]
      ['Konfeti Indie Fest Yogyakarta', 'Hindia', 'Hindia, Feast, Nadin Amizah', 'Indie', 'Alun-Alun Utara, Yogyakarta', -7.8047, 110.3646, 1, _addDays(14), _addDays(14.25), 275000, 600],
      ['Pop Legends Double Show', 'Raisa', 'Raisa, Tulus', 'Pop', 'Jogja Expo Center', -7.7981, 110.4086, 0, _addDays(18), _addDays(18.2), 500000, 250],
    ];

void _ensureLineupEvents(AppDb db) {
  var added = 0;
  for (final e in _lineupEvents()) {
    final exists = db.one('SELECT id FROM events WHERE title=?', <Object?>[e[0]]);
    if (exists != null) {
      db.run('UPDATE events SET lineup=? WHERE id=?', <Object?>[e[2], exists['id']]);
      continue;
    }
    db.run(
      '''INSERT INTO events(title,artist,lineup,category,venue_name,latitude,longitude,is_outdoor,
                      start_time_utc,end_time_utc,price_idr,stock)
   VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
      e,
    );
    added++;
  }
  print('Lineup demo events added: $added');
}

const List<List<Object?>> _promos = <List<Object?>>[
  ['KONFETI10', 'Welcome promo: 10% off your tickets', 10],
  ['STUDENT20', 'Student discount: 20% off', 20],
  ['WEEKEND15', 'Weekend special: 15% off', 15],
];

void main(List<String> args) {
  Env.load();
  final db = AppDb.open();

  if (args.contains('--reset')) {
    // hapus data yang bergantung pada events (urutan penting karena foreign key)
    for (final t in <String>['emergency_alerts', 'blocks', 'tickets', 'transactions', 'notifications', 'events']) {
      db.run('DELETE FROM $t');
    }
    print('Events, orders, tickets, blocks, and notifications cleared (users are kept).');
  }

  for (final p in _promos) {
    db.run('INSERT OR IGNORE INTO promos(code,description,discount_percent) VALUES(?,?,?)', p);
  }

  final count = db.one('SELECT COUNT(*) AS n FROM events')!['n'] as int;
  if (count > 0) {
    print('Events table already has $count rows (use "dart run bin/seed.dart --reset" to reseed).');
  } else {
    final events = _events();
    db.transaction<void>(() {
      for (final e in events) {
        db.run(
          '''INSERT INTO events(title,artist,category,venue_name,latitude,longitude,is_outdoor,
                      start_time_utc,end_time_utc,price_idr,stock)
   VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
          e,
        );
      }
    });
    print('Seeded ${events.length} events and ${_promos.length} promo codes.');
  }
  _ensureLineupEvents(db);
}
