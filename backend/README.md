# Konfeti Backend (Dart)

REST API untuk aplikasi Konfeti, ditulis dengan **Dart murni** (`dart:io` + SQLite).
Kontrak JSON sama persis dengan versi Node.js sebelumnya, jadi aplikasi Flutter tidak perlu diubah.

## Syarat
- Dart SDK **3.10 atau lebih baru** (cek: `dart --version`). Sudah termasuk kalau Flutter kamu terbaru.

## Menjalankan (Windows PowerShell / CMD)
```bash
cd backend
dart pub get
copy .env.example .env      # lalu isi JWT_SECRET dan API key milikmu
dart run bin/seed.dart      # isi 11 event + 3 promo (tambah --reset untuk mengulang dari nol)
dart run bin/server.dart    # server jalan di http://localhost:3000
```
Cek: buka http://localhost:3000/api/health

## Tes alur penuh
Biarkan server tetap jalan, buka terminal baru:
```bash
dart run test/smoke.dart
```
Hasil yang diharapkan: `0 failed`. Tes ini tidak butuh API key (pembayaran disimulasikan, butuh `ALLOW_DEV_ROUTES=true` di `.env`).

## Kategori tiket & gambar artis
- Tiap event punya kategori tiket (tabel `ticket_tiers`): artis besar banyak kategori (CAT, Festival, VIP), artis kecil hanya 1. Saat order, app mengirim `tier_id`.
- `dart run bin/seed.dart` juga melengkapi kategori untuk database lama (tanpa menghapus data).
- Gambar artis diambil dari Spotify saat seed (butuh `SPOTIFY_CLIENT_ID/SECRET` di `.env`). Ulangi kapan saja dengan `dart run bin/seed.dart --images`. Bisa juga isi alamat gambar manual di `_manualImages` pada `bin/seed.dart`.

## Struktur
- `bin/server.dart` : titik masuk server, `bin/seed.dart` : data awal
- `lib/src/web.dart` : router, CORS, rate limit, static `/uploads`
- `lib/src/routes/` : auth, events, orders, tickets, notifications, promos, feedback, emergency, rates, weather, spotify, chat
- `lib/src/services/` : blockchain tiket, penyelesaian order (idempoten)
- `test/smoke.dart` : tes HTTP

## Catatan
- Database lama `app.db` dari versi Node kompatibel (skema sama). Hash password lama (bcrypt) tetap bisa login.
- Jangan commit `.env`. Kalau kunci API pernah bocor, buat ulang kuncinya.
