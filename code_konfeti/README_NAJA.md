# Bagian Naja — alur inti tiket (Flutter)

## 1. Pasang dependensi (jalankan di folder `code_konfeti`)
```bash
flutter pub add http flutter_secure_storage intl timezone url_launcher qr_flutter sensors_plus geolocator audioplayers google_fonts
flutter pub get
```
(`pub add` otomatis memilih versi terbaru yang cocok dengan SDK kamu.)

## 2. Jalankan
1. Backend: `cd backend && dart run bin/seed.dart && dart run bin/server.dart`
2. Emulator Android: `flutter run`  (otomatis memakai http://10.0.2.2:3000)
3. HP fisik: `flutter run --dart-define=API_URL=http://<IP-LAN-laptop>:3000` (HP & laptop satu Wi-Fi)
4. Saat presentasi, detail tiket bisa dibuka kapan saja (`DEMO_UNLOCK=true`, default).
   Untuk perilaku asli (hanya saat event berlangsung): `--dart-define=DEMO_UNLOCK=false`

## 3. Struktur
```
lib/
  main.dart                      entry + AuthGate (Session)
  core/    config, api_client (JWT otomatis), session (secure storage), formatters
  models/  event.dart (Event, Order, Ticket)
  services/time_zones.dart       konversi WIB / WITA / WIT / London
  features/
    shell/     navbar 5 tab + ShellNav (pindah tab)
    home/      Home (search, sort, filter), detail event, kartu waktu 4 zona
    checkout/  qty, promo, konversi mata uang, buat order, buka Midtrans
    tickets/   My Tickets (3 tab), detail tiket + QR, shake_detector, emergency_dialog
    auth/      login_page SEMENTARA -> ganti dengan halaman Ilham
```

## 4. Titik sambung dengan Ilham & Danu
- **Ilham**: ganti `features/auth/login_page.dart`. Cukup panggil `Session.instance.login(email, pass)` /
  `register(name, email, pass)`; `main.dart` otomatis pindah ke `MainShell` saat `loggedIn` true.
  Untuk login biometrik: setelah lolos `local_auth`, ambil token dari secure storage lalu `Session.instance.restore()`.
- **Danu**: ganti `_Placeholder` (AI Chat, Entertainment) dan `_ProfilePlaceholder` di `features/shell/main_shell.dart`.
  Slot cuaca + peta venue ada di `event_detail_page.dart` (komentar `TODO(Danu)`).
  Panggilan API pakai `ApiClient.instance.get/post/put` supaya token ikut terkirim.

## 5. Midtrans (mode asli)
Isi `MIDTRANS_SERVER_KEY` di `backend/.env`. Status order hanya berubah lewat webhook Midtrans, jadi backend harus
punya URL publik (ngrok) dan di dashboard Midtrans sandbox **Payment Notification URL** diisi
`https://<ngrok>/api/orders/notification`. Tanpa key + `ALLOW_DEV_ROUTES=true`, checkout memakai "demo payment".

## 6. Checklist dosen yang tercakup
| No | Kriteria | Di mana |
|----|----------|---------|
| 7 | Konversi mata uang (IDR, USD, EUR, JPY, SGD, MYR) | `checkout_page.dart` (`/api/rates`) |
| 7 | Konversi waktu (WIB, WITA, WIT, London) | `time_zones.dart`, `event_times_card.dart` |
| 8 | Accelerometer (shake darurat) | `shake_detector.dart`, `ticket_detail_page.dart` |
| 8 | Gyroscope (rotasi layar) | `ticket_detail_page.dart` |
| 11 | Pencarian, sorting, filter | `home_page.dart` |
| 6 | Bottom navigation | `main_shell.dart` |

## 7. Pembaruan
- Tiket aktif/history: 1 kartu per order (`groupTickets`), detail menampilkan semua tiket (geser).
- Palet Color Hunt: `core/app_theme.dart` (#006199, #8ACFF8, #F4EB6C, #FFD444).
- Spotify di detail tiket: `features/tickets/artist_section.dart` (`/api/spotify/artist`; preview jika tersedia, selain itu buka di Spotify).
- Sensor global: `services/sensor_service.dart` dijalankan dari `main.dart` selama login (accelerometer = darurat, gyroscope = rotasi layar, di semua halaman).

## 8. Redesign (design system) & lineup
- Tema dark sesuai `konfeti_app_design_system.md`: `core/app_theme.dart` (warna + font Poppins via `google_fonts`), komponen bersama di `core/widgets.dart` (AppCard, CategoryPill, Tag, RotateButton).
- Home: Live/Featured hero, Nearby Events (butuh izin lokasi; disembunyikan jika ditolak), Upcoming Events (grid).
- Detail konser: hero + tombol back/favorite, lineup artis + profil Spotify per artis (`ArtistSection`), peta venue statis, bottom bar harga + Buy Ticket.
- E-Ticket putih dengan efek sobekan; QR tetap yang dipindai, barcode hanya dekorasi.
- Lineup multi-artis: kolom baru `events.lineup` (dipisah koma). Migrasi otomatis saat backend start.
  Jalankan `dart run bin/seed.dart` (TANPA --reset) untuk menambah 2 event demo: "Konfeti Indie Fest" (3 artis) dan "Pop Legends Double Show" (2 artis).
- Gyroscope aktif di semua halaman (termasuk login) + tombol rotasi di setiap halaman utama; threshold di `SensorService.twistThreshold`.
