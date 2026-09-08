# BrowserNote — Alur Kerja Pengembangan

## 1. Tujuan

BrowserNote adalah aplikasi notepad berbasis web yang sangat ringan untuk mencatat potongan kode, konfigurasi, perintah terminal, teks, tabel, tautan, dan catatan kerja lain langsung dari browser.

Prinsip utama aplikasi:

- tanpa login
- tanpa register
- langsung membuka ruang editor
- autosave
- full browser
- antarmuka minimal
- folder untuk pengelompokan catatan
- arsip untuk catatan yang tidak aktif
- sampah untuk penghapusan aman
- pencarian judul dan isi
- rich text editor lengkap
- tabel lengkap
- code block
- berjalan lokal melalui XAMPP
- tidak bergantung CDN untuk editor

## 2. Stack

Backend

- PHP
- CodeIgniter 4
- SQLite

Frontend

- HTML
- CSS native
- JavaScript native
- TinyMCE self-hosted

Server lokal

- XAMPP Apache

Lokasi proyek

```text
C:\xampp\htdocs\browsernote
```

Base URL

```text
http://localhost/browsernote/public/
```

Database

```text
C:\xampp\htdocs\browsernote\writable\browsernote.sqlite
```

## 3. Filosofi UI

Aplikasi bukan dashboard administratif.

Alur utama:

```text
Buka browser
    ↓
BrowserNote terbuka
    ↓
Catatan terakhir atau catatan baru langsung tersedia
    ↓
Ketik
    ↓
Autosave
    ↓
Kelompokkan ke folder jika diperlukan
    ↓
Arsipkan jika selesai
```

Tampilan desktop:

```text
┌───────────────────────────────────────────────────────────────────────┐
│ BrowserNote   + Baru   Cari                         Arsip   Pengaturan │
├──────────────────┬────────────────────────────────────────────────────┤
│ SIDEBAR          │ Judul catatan                                      │
│                  ├────────────────────────────────────────────────────┤
│ Terbaru          │ Toolbar editor                                     │
│                  ├────────────────────────────────────────────────────┤
│ Folder           │                                                    │
│  OJS             │               EDITOR FULL HEIGHT                   │
│  Flutter         │                                                    │
│  VPS             │                                                    │
│                  │                                                    │
│ Arsip            │                                                    │
│ Sampah           │                                                    │
├──────────────────┴────────────────────────────────────────────────────┤
│ Tersimpan otomatis                                      jumlah karakter│
└───────────────────────────────────────────────────────────────────────┘
```

Sidebar dapat diciutkan. Saat sidebar ditutup editor menggunakan hampir seluruh lebar browser.

## 4. Struktur Data

### folders

```text
id
name
sort_order
created_at
updated_at
```

### notes

```text
id
folder_id
title
content
content_text
is_archived
is_deleted
created_at
updated_at
archived_at
deleted_at
```

Keterangan penting:

- `content` menyimpan HTML TinyMCE.
- `content_text` menyimpan versi plain text untuk pencarian cepat.
- `folder_id` boleh kosong.
- `is_archived` menentukan status arsip.
- `is_deleted` menentukan status sampah.

## 5. Endpoint Aplikasi

Rencana endpoint utama:

```text
GET    /                         membuka aplikasi
GET    /api/notes               daftar catatan
POST   /api/notes               membuat catatan
GET    /api/notes/{id}          membaca catatan
PATCH  /api/notes/{id}          autosave dan perubahan catatan
DELETE /api/notes/{id}          memindahkan ke sampah

POST   /api/notes/{id}/archive
POST   /api/notes/{id}/restore
POST   /api/notes/{id}/restore-trash
DELETE /api/notes/{id}/force

GET    /api/folders
POST   /api/folders
PATCH  /api/folders/{id}
DELETE /api/folders/{id}

GET    /api/search?q=...
```

## 6. Tahapan Pengerjaan

### Stage 00 — Preflight

Tujuan:

- memastikan XAMPP tersedia
- memastikan PHP tersedia
- memastikan Composer tersedia
- memastikan ekstensi SQLite aktif
- memastikan folder `htdocs` tersedia

Kriteria PASS:

```text
PHP OK
Composer OK
SQLite3 OK
htdocs OK
```

### Stage 01 — Foundation

Tujuan:

- membuat proyek CodeIgniter 4
- mengatur base URL
- mengatur SQLite
- membuat shell full-browser
- membuat sidebar dasar
- membuat area editor placeholder
- membuat CSS dasar
- memastikan route root berjalan

Output utama:

```text
C:\xampp\htdocs\browsernote
```

Kriteria PASS:

```text
http://localhost/browsernote/public/
```

dapat dibuka dan menampilkan shell BrowserNote.

### Stage 02 — Database dan Model

Tujuan:

- migration `folders`
- migration `notes`
- model FolderModel
- model NoteModel
- seed catatan awal opsional
- index pencarian
- foreign key

Kriteria PASS:

- migration sukses
- SQLite terbentuk
- create/read/update/delete dasar berhasil

### Stage 03 — API Catatan

Tujuan:

- endpoint daftar catatan
- endpoint catatan tunggal
- membuat catatan
- memperbarui catatan
- soft delete ke Sampah
- restore
- force delete
- response JSON konsisten

Kriteria PASS:

- catatan dapat dibuat melalui API
- catatan dapat dimuat kembali
- perubahan tersimpan ke SQLite

### Stage 04 — TinyMCE Self-Hosted

Tujuan:

- memasang TinyMCE secara lokal
- tidak memakai CDN
- editor mengisi tinggi browser
- toolbar ringkas tetapi lengkap
- tabel
- heading
- bold
- italic
- underline
- strikethrough
- list
- checklist jika tersedia
- link
- blockquote
- code
- code block
- search replace
- fullscreen
- undo redo
- clear formatting

Tabel harus mendukung:

- insert table
- tambah baris
- tambah kolom
- hapus baris
- hapus kolom
- merge cells
- split cells
- header row
- delete table

Kriteria PASS:

- tabel dapat dibuat dan diedit
- isi editor dapat dikirim ke backend
- editor tetap cepat

### Stage 05 — Autosave

Tujuan:

- autosave debounce sekitar 700 ms
- indikator `Menyimpan...`
- indikator `Tersimpan`
- indikator gagal
- tidak membuat request setiap karakter
- mencegah race condition
- penyimpanan terakhir menang

Kriteria PASS:

- mengetik lalu berhenti otomatis menyimpan
- refresh browser memuat isi terakhir

### Stage 06 — Local Recovery

Tujuan:

- draft sementara disimpan di browser
- LocalStorage atau IndexedDB sebagai safety cache
- jika request backend gagal, draft lokal tidak hilang
- setelah backend pulih, pengguna dapat melanjutkan

Kriteria PASS:

- refresh tidak menghilangkan perubahan penting
- kegagalan server tidak langsung menghilangkan draft

### Stage 07 — Folder

Tujuan:

- buat folder
- rename folder
- hapus folder
- pindahkan catatan ke folder
- catatan tanpa folder tetap diperbolehkan
- jumlah catatan per folder

Contoh:

```text
Flutter
OJS
CodeIgniter
Server VPS
PowerShell
```

Kriteria PASS:

- catatan dapat berpindah folder tanpa kehilangan isi

### Stage 08 — Arsip dan Sampah

Arsip:

- catatan selesai dapat diarsipkan
- catatan arsip tidak mengganggu daftar aktif
- arsip dapat dipulihkan

Sampah:

- delete tidak langsung menghapus permanen
- restore dari sampah
- hapus permanen dilakukan eksplisit

Kriteria PASS:

- archive/restore berjalan
- trash/restore berjalan
- force delete berjalan

### Stage 09 — Pencarian

Tujuan:

- pencarian judul
- pencarian isi
- pencarian real time
- hasil diurutkan berdasarkan relevansi sederhana dan waktu perubahan
- klik hasil membuka catatan

Kriteria PASS:

- potongan kode atau istilah di dalam isi dapat ditemukan

Contoh pencarian:

```text
citationsRaw
flutter build
SMTP 587
migration
```

### Stage 10 — Quick Note dan Keyboard Shortcut

Shortcut:

```text
Ctrl + N     catatan baru
Ctrl + S     simpan sekarang
Ctrl + F     pencarian
Ctrl + Shift + A  arsipkan
Esc          tutup dialog
```

Perilaku Quick Note:

- tidak wajib menentukan folder
- tidak wajib menentukan judul
- judul sementara `Catatan tanpa judul`
- judul dapat diganti kapan saja

Kriteria PASS:

- membuat catatan baru tidak membutuhkan modal panjang

### Stage 11 — Export dan Backup

Export per catatan:

```text
.txt
.html
```

Opsional setelah fungsi inti stabil:

```text
.md
```

Backup keseluruhan:

- database SQLite
- ekspor JSON
- restore JSON

Kriteria PASS:

- seluruh data dapat dicadangkan
- catatan individual dapat diekspor

### Stage 12 — UI Polish

Fokus:

- full width
- full height
- sidebar 230–260 px
- sidebar collapse
- editor tanpa card berlebihan
- tanpa Bootstrap
- tanpa animasi berat
- toolbar satu baris bila ruang cukup
- responsive desktop/laptop
- dark mode
- light mode
- status autosave kecil
- scroll yang benar
- fokus editor tidak terganggu

Kriteria PASS:

- area utama terasa seperti editor, bukan dashboard
- tidak ada ruang kosong besar
- layout tetap rapi pada 1366×768 dan 1920×1080

### Stage 13 — Performance dan Hardening Lokal

Tujuan:

- query minimal
- pagination atau lazy loading jika catatan banyak
- debounce search
- escape output yang bukan HTML editor
- validasi request
- CSRF untuk request perubahan
- ukuran payload wajar
- sanitasi HTML editor
- backup database

Catatan:

Karena aplikasi tidak memakai autentikasi, deployment awal ditujukan untuk localhost. Jangan mengekspos aplikasi ini ke internet publik tanpa lapisan proteksi tambahan.

### Stage 14 — Final UAT

Skenario uji:

1. buka aplikasi
2. buat catatan
3. tulis teks
4. paste kode
5. buat tabel
6. autosave
7. refresh
8. buka kembali
9. buat folder
10. pindahkan catatan
11. cari isi catatan
12. arsipkan
13. restore
14. hapus
15. restore dari sampah
16. hapus permanen
17. export
18. backup
19. uji sidebar collapse
20. uji resolusi 1366×768 dan 1920×1080

Kriteria final:

```text
Semua fungsi inti PASS
Tidak ada kehilangan data
Tidak ada login/register
Buka URL langsung ke editor
Autosave stabil
Editor full-browser
Tabel berfungsi lengkap
Pencarian cepat
```

## 7. Urutan Script PowerShell

Rencana file:

```text
01_BROWSERNOTE_FOUNDATION.ps1
02_BROWSERNOTE_DATABASE.ps1
03_BROWSERNOTE_NOTES_API.ps1
04_BROWSERNOTE_TINYMCE.ps1
05_BROWSERNOTE_AUTOSAVE.ps1
06_BROWSERNOTE_LOCAL_RECOVERY.ps1
07_BROWSERNOTE_FOLDERS.ps1
08_BROWSERNOTE_ARCHIVE_TRASH.ps1
09_BROWSERNOTE_SEARCH.ps1
10_BROWSERNOTE_SHORTCUTS.ps1
11_BROWSERNOTE_EXPORT_BACKUP.ps1
12_BROWSERNOTE_UI_POLISH.ps1
13_BROWSERNOTE_HARDENING.ps1
14_BROWSERNOTE_FINAL_UAT.ps1
```

Setiap stage harus:

- memiliki precheck
- membuat backup file yang akan ditimpa bila perlu
- menghentikan proses jika precheck kritis gagal
- menjalankan verifikasi
- menampilkan PASS atau FAIL
- tidak melanjutkan diam-diam jika hasil utama gagal

## 8. Struktur Folder Target

```text
browsernote/
├── app/
│   ├── Config/
│   ├── Controllers/
│   ├── Database/
│   │   ├── Migrations/
│   │   └── Seeds/
│   ├── Models/
│   └── Views/
│       └── notes/
├── public/
│   ├── assets/
│   │   ├── css/
│   │   ├── js/
│   │   └── vendor/
│   │       └── tinymce/
│   └── index.php
├── writable/
│   └── browsernote.sqlite
├── vendor/
├── .env
├── composer.json
└── spark
```

## 9. Keputusan Arsitektur yang Dikunci

- Framework memakai CodeIgniter 4.
- Database awal memakai SQLite.
- Base URL memakai `http://localhost/browsernote/public/`.
- Proyek berada di `C:\xampp\htdocs\browsernote`.
- Editor memakai TinyMCE self-hosted.
- Tidak memakai Bootstrap.
- Tidak memakai login.
- Tidak memakai register.
- Tidak memakai dashboard statistik.
- Tidak memakai CDN untuk komponen editor utama.
- Autosave adalah mekanisme penyimpanan utama.
- Folder adalah pengelompokan catatan.
- Arsip adalah status catatan selesai/tidak aktif.
- Sampah adalah penghapusan sementara.
- UI memanfaatkan seluruh area browser.

## Stage 15 — Kenyamanan Menulis (8 September 2026)

Implementasi:
- Tombol **Tampilan** membuka dialog pengaturan ruang menulis.
- Mode Menulis terpusat: area teks 760 px pada desktop (820 px termasuk padding), responsif pada layar kecil. Lebar penuh tetap tersedia untuk kode dan tabel.
- Tema terang, sepia, dan gelap; font Segoe UI atau Georgia; ukuran 16/18/20/22 px; jarak baris 1,5/1,7/2.
- Preferensi tersimpan di `browsernote.appearance.v1` pada localStorage dan diterapkan kembali setelah reload. Tombol reset mengembalikan tema terang, sans-serif 18 px, jarak 1,7, dan lebar terpusat.
- Tombol **Fokus** menyembunyikan sidebar, toolbar, serta aksi pengelolaan catatan. **Keluar Fokus** atau **Esc** di editor mengembalikan tampilan sebelumnya. Status simpan tetap terlihat. Mode Fokus berlaku selama sesi halaman; kondisi sidebar sebelumnya tetap dipertahankan.
- Preferensi diterapkan pada dokumen editor, bukan pada HTML isi catatan; tidak mengubah format tersimpan atau hasil ekspor. Format eksplisit pada teks tetap berlaku.
- Jumlah kata ditampilkan sekali di statusbar aplikasi; label antarmuka diperbesar dan label teknis editor dihapus.
- Pada layar <=760 px, sidebar awalnya ditutup dan dapat dibuka sebagai panel. Tombol aksi tetap memiliki label yang terbaca.
- Skrip polish lama menunggu editor selesai inisialisasi sebelum mengakses seleksi.

Berkas utama: `writing-preferences.js`, `writing-preferences.css`, `writing-content.css`, serta integrasi di view dan inisialisasi TinyMCE.

Git lokal:
- Commit awal sebelum perubahan: `6b51b6d`.
- `.env`, database SQLite, backup, dan laporan runtime tidak masuk Git.
- TinyMCE self-hosted masuk Git; dependensi Composer `/vendor/` diabaikan.

Validasi: syntax check JavaScript/PHP, pemeriksaan browser pada desktop dan viewport 390 x 844, autosave dan reload catatan uji, persistensi preferensi, tema dan tipografi, lebar penuh, reset, serta keluar fokus melalui Escape.

### Koreksi posisi awal tulisan

Sesuai preferensi pengguna, bawaan dan reset kini memakai lebar penuh dengan tulisan dimulai 20 px dari sisi kiri editor. Pengaturan lama dimigrasikan satu kali ke lebar penuh (`layoutVersion: 2`), dengan tema, font, ukuran, dan jarak baris tetap dipertahankan. Mode terpusat tetap tersedia sebagai pilihan manual di Tampilan. Jarak atas untuk lebar penuh dikurangi menjadi 22 px.

## Stage 16 — Script Deploy SSH untuk note.sil.web.id

Referensi: script dan panduan deploy proyek lokal `plpi-public`. Implementasi BrowserNote menggunakan `deploy-cpanel.sh` dengan action `check`, `install`, dan `update`, serta paket source yang dapat dibuat lewat `script/BUILD_DEPLOY_PACKAGE.ps1`.

- Aplikasi berada di luar webroot dengan release terpisah; hanya `public/` diterbitkan ke folder domain.
- SQLite, .env, dan password situs berada di shared storage yang dipertahankan saat update.
- Akses editor/API/backup melalui HTTPS dilindungi Apache Basic Auth sesuai pilihan pengguna. Password diisi langsung pada terminal hosting.
- Setiap deploy membuat backup webroot, konfigurasi, dan snapshot SQLite. Migrasi berjalan dalam maintenance; kegagalan tidak otomatis membuka kembali situs.
- Paket tidak berisi catatan/database lokal, .env lokal, atau vendor Composer. Dependensi dipasang dari composer.lock pada hosting.
- Panduan lengkap, syarat hosting, dan pemulihan kegagalan ada di `DEPLOY_SSH.md`.

Validasi lokal: syntax Bash/PHP dan konfigurasi Apache lulus; 15 pemeriksaan helper mencakup pemeliharaan .env, key unik, penolakan path salah, patch front controller, konfigurasi autentikasi/HTTPS, migrasi berulang, snapshot WAL, integritas backup, dan penolakan database tidak sesuai. Isi paket diperiksa agar tidak memuat data lokal. Koneksi SSH, DNS/SSL, PHP-FPM, dan deploy pada hosting belum dijalankan.

Wrapper `script/DEPLOY_VIA_SSH.ps1` dapat membangun paket, memvalidasi isinya, mengunggah lewat SCP, lalu menjalankan action `check`, `install`, atau `update` pada terminal SSH. Host, user, port, dan username Basic Auth diberikan sebagai parameter; password tetap diisi melalui prompt interaktif.

Hosting yang tidak menyediakan `rsync` didukung melalui fallback tar/copy. Sebelum fallback membersihkan isi webroot, script tetap memvalidasi path dan marker kepemilikan deployment; `.well-known`, marker deployment, maintenance, dan front controller aktif dipertahankan sampai release baru siap.

Jika Composer global tidak tersedia, action `check` memvalidasi tersedianya curl, wget, atau `allow_url_fopen`. Action `install` kemudian mengunduh installer Composer resmi, memverifikasi checksum SHA-384, dan memasang Composer 2 di private shared tools tanpa akses root.

Deploy mengenali konfigurasi bawaan cPanel di webroot. File `.user.ini`, `php.ini`, folder `cgi-bin` dan `.well-known` dipertahankan; blok bertanda cPanel-generated dari `.htaccess` lama digabungkan ke htaccess BrowserNote agar pengaturan PHP domain tidak hilang.

Jika command Apache `htpasswd` tidak tersedia pada shared hosting, deploy meminta password dua kali secara tersembunyi dan membuat entri `.htpasswd` bcrypt yang kompatibel melalui PHP.

Tooltip bantuan aplikasi tersedia untuk kontrol yang memerlukan penjelasan, termasuk sidebar, folder, aksi catatan, mode fokus, tampilan, dan simpan. Tooltip tampil melalui hover maupun fokus keyboard, diposisikan terhadap viewport agar tidak terpotong oleh sidebar, dan tombol dinamis tetap memiliki label aksesibilitas.

Favicon BrowserNote tersedia dalam SVG, PNG 32 px, ICO, dan Apple Touch Icon 180 px. Halaman memasang ikon dengan URL berversi agar favicon bawaan hosting segera diganti setelah deploy.
