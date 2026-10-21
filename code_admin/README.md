# Konfeti Admin (`code_admin`)

Aplikasi admin untuk Konfeti. Hanya client: semua data lewat endpoint `/api/admin/*` di `backend/`.

> Status: kode ini **belum pernah dikompilasi atau dijalankan** (ditulis tanpa Flutter SDK). Kemungkinan ada error kecil saat `flutter analyze`; kirim pesan errornya untuk diperbaiki.

## Menjalankan (tanpa langkah tambahan)
Folder ini sudah lengkap (termasuk `android/` dan `web/`). Cukup:

```
cd code_admin
flutter pub get
flutter run
```

Backend harus hidup dulu (`dart run bin/server.dart` di folder `backend`) dan sudah memakai versi terbaru (ada endpoint admin dan kolom baru di database).

- Emulator Android: `flutter run` (otomatis memakai `http://10.0.2.2:3000`)
- Web: `flutter run -d chrome` (memakai `http://localhost:3000`)
- HP fisik: `flutter run --dart-define=API_URL=http://IP-LAPTOP:3000`

Port 3000 mengikuti `PORT` di `backend/.env`. Izin internet, kamera (scan QR), dan `usesCleartextTraffic` (backend lokal memakai http) sudah diatur di `android/app/src/main/AndroidManifest.xml`. Hapus `usesCleartextTraffic` untuk produksi.

## Akun admin
Dibuat lewat backend: `dart run bin/create_admin.dart` (di folder `backend`).

## Fitur
- Dashboard: sapaan, aksi cepat, ringkasan, daftar "perlu perhatian", grafik penjualan
- Events: tambah, ubah, hapus, kategori tiket, status draft/active/cancelled
- Check-in: scan QR atau ketik kode, verifikasi ke server, tampilkan data pembawa tiket (nama, NIK disamarkan, umur, gender)
- Blockchain: status rantai dan daftar blok
- Emergency: alert SOS dari penonton, lokasi di peta, tombol "Tanggapi" (penonton menerima notifikasi)
- Orders, Users, Promos, Broadcast, Feedback, Activity log
