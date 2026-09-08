# Deploy BrowserNote ke note.sil.web.id melalui SSH

Script ini mengikuti pemisahan aplikasi dan webroot pada `plpi-public/deploy-cpanel.sh`, disesuaikan untuk SQLite, release terpisah, dan akses dengan password. Jalankan script di Linux hosting melalui SSH atau Terminal cPanel. Tidak perlu MySQL atau remote Git untuk cara upload paket.

## Folder di hosting

| Kegunaan | Default |
| --- | --- |
| Source yang diunggah | `$HOME/browsernote-deploy-src-<waktu>` |
| Aplikasi dan release | `$HOME/browsernote-app/releases/<waktu>` |
| Database dan writable bersama | `$HOME/browsernote-app/shared/writable` |
| Konfigurasi production | `$HOME/browsernote-app/shared/.env` |
| Hash password situs | `$HOME/browsernote-app/shared/.htpasswd` |
| Document root domain | `$HOME/note.sil.web.id` |
| Backup setiap deploy | `$HOME/backups/browsernote-deploy/<waktu>` |

Di cPanel, buat domain/subdomain `note.sil.web.id`, aktifkan sertifikat SSL, dan arahkan document root ke folder webroot di atas. Gunakan folder khusus domain, bukan document root situs lain. Bila hosting menetapkan path berbeda, isi `WEB_DIR` dengan path sebenarnya pada setiap perintah. App, source, dan backup harus berada di luar webroot; app dan backup juga ditolak bila berada di `public_html`.

PHP **8.2 atau lebih baru**, ekstensi **intl, mbstring, sqlite3, fileinfo, openssl**, serta Bash, tar, realpath, Composer, dan htpasswd harus tersedia. `rsync` dipakai bila tersedia; jika tidak, script otomatis memakai fallback tar/copy. Versi PHP di MultiPHP Manager harus sesuai dengan PHP CLI yang dipakai script. Script ditujukan untuk Apache 2.4 atau hosting yang mendukung directive `.htaccess` Apache termasuk Basic Auth dan `<If>`, dengan HTTPS langsung pada webserver. Konfigurasi reverse proxy/TLS termination perlu disesuaikan oleh hosting.

## 1. Buat paket di Windows

Dari folder proyek:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\script\BUILD_DEPLOY_PACKAGE.ps1
```

Hasil ada di `build/browsernote-deploy-<waktu>.tar.gz`. Paket mengambil **kode workspace saat ini**, termasuk editor TinyMCE lokal. `.env`, database SQLite, backup, catatan lokal, dependensi Composer, dan riwayat Git tidak disertakan. Instalasi pertama membuat database kosong; update mempertahankan catatan di hosting.

## 2. Upload dan masuk SSH

Ganti `USER_CPANEL`, `HOST_SSH`, `PORT_SSH`, dan nama paket dengan data akun hosting. Host SSH dapat berbeda dari domain situs. Tidak ada username/host SSH yang diasumsikan sama dengan akun PLPI.

```powershell
scp -P PORT_SSH .\build\browsernote-deploy-<waktu>.tar.gz USER_CPANEL@HOST_SSH:~/browsernote-upload.tar.gz
ssh -t -p PORT_SSH USER_CPANEL@HOST_SSH
```

Verifikasi fingerprint SSH sesuai informasi hosting saat koneksi pertama. Script tidak mengatur atau menonaktifkan pemeriksaan host key.

Cara paling singkat adalah memakai wrapper PowerShell. Wrapper membuat paket baru, memeriksa agar `.env`, SQLite, `writable`, dan `vendor` tidak ikut, mengunggahnya, mengekstrak ke source baru, kemudian menjalankan action melalui SSH:

```powershell
.\script\DEPLOY_VIA_SSH.ps1 `
    -SshHost HOST_SSH `
    -SshUser USER_CPANEL `
    -SshPort PORT_SSH `
    -Action check
```

Setelah `check` lulus, lakukan pemasangan pertama. Terminal akan meminta autentikasi SSH dan kemudian password baru untuk BrowserNote:

```powershell
.\script\DEPLOY_VIA_SSH.ps1 `
    -SshHost HOST_SSH `
    -SshUser USER_CPANEL `
    -SshPort PORT_SSH `
    -Action install `
    -AuthUser penulis
```

Untuk update berikutnya, ganti action menjadi `update`. Jika memakai private key tertentu, tambahkan `-IdentityFile C:\path\key`. Wrapper mempertahankan pemeriksaan host key bawaan OpenSSH.

Di terminal SSH:

```bash
SOURCE_DIR="$HOME/browsernote-deploy-src-$(date +%Y%m%d-%H%M%S)"
mkdir "$SOURCE_DIR"
tar -xzf "$HOME/browsernote-upload.tar.gz" -C "$SOURCE_DIR"
cd "$SOURCE_DIR"
bash deploy-cpanel.sh check
bash deploy-cpanel.sh install
```

`check` memeriksa command, ekstensi, source, lokasi folder, kepemilikan deployment, dan Composer tanpa mengubah file hosting. Pemeriksaan ini belum membuktikan konfigurasi PHP-FPM, SSL, atau document root domain.

`install` meminta password untuk username **penulis** melalui prompt `htpasswd`. Password tidak ditampilkan, tidak dimasukkan ke argumen command, dan tidak disimpan dalam Git. Gunakan `AUTH_USER=namaanda bash deploy-cpanel.sh install` untuk username berbeda saat pertama kali memasang. Ini satu pintu password untuk kumpulan catatan bersama, bukan akun terpisah per penulis.

Jika PHP default hosting terlalu lama:

```bash
PHP_BIN=/opt/cpanel/ea-php82/root/usr/bin/php \
COMPOSER_BIN=/opt/cpanel/composer/bin/composer \
WEB_DIR="$HOME/note.sil.web.id" \
bash deploy-cpanel.sh install
```

Path PHP/Composer contoh tersebut harus benar-benar tersedia di hosting. `COMPOSER_BIN` harus berupa file entry point PHP Composer atau `composer.phar`, bukan command beserta argumennya. Script tidak mengunduh executable Composer secara otomatis.

Webroot pertama kali harus kosong, kecuali `.well-known`. Jika ada `index.html` bawaan hosting, pindahkan dahulu ke folder backup di luar webroot. Script menolak menimpa situs yang belum ditandai sebagai deployment BrowserNote.

## 3. Update berikutnya

Buat paket baru di Windows, upload ulang, kemudian dari SSH:

```bash
SOURCE_DIR="$HOME/browsernote-deploy-src-$(date +%Y%m%d-%H%M%S)"
mkdir "$SOURCE_DIR"
tar -xzf "$HOME/browsernote-upload.tar.gz" -C "$SOURCE_DIR"
cd "$SOURCE_DIR"
bash deploy-cpanel.sh update
```

Gunakan nilai `APP_DIR`, `WEB_DIR`, `BACKUP_DIR`, `PHP_BIN`, dan `COMPOSER_BIN` yang sama jika sebelumnya dikustomisasi. Perintah di atas selalu memakai folder source baru yang kosong, sehingga file kode yang sudah dihapus tidak tertinggal dari versi sebelumnya. Folder source tidak boleh berada di dalam app/webroot/backup.

Script menyiapkan release baru dan dependency dari `composer.lock`, membuat backup webroot serta `.env`/hash password, mengaktifkan maintenance singkat, mengambil snapshot SQLite dengan SQLite backup API, menjalankan migrasi yang belum diterapkan, lalu menerbitkan hanya `public/`. Front controller diganti terakhir. `.well-known`, `.env` hosting, password, database, dan upload hosting dipertahankan. Tidak ada import database lokal atau seed otomatis.

Database berada di shared writable, bukan di folder release. Release lama dan backup tidak dihapus otomatis; pantau kuota hosting sebelum menghapus backup lama secara manual.

## Password dan pemeriksaan hasil

Untuk mengganti password nanti, jalankan sendiri dari terminal hosting:

```bash
htpasswd -B "$HOME/browsernote-app/shared/.htpasswd" penulis
```

File `.htpasswd` berisi hash, disimpan di luar webroot, dan dibuat readable oleh Apache. `.env` dan file database memakai izin 600; folder writable/backup memakai 700. Script mengasumsikan PHP hosting berjalan sebagai user cPanel yang sama.

Setelah deploy:

1. Buka `https://note.sil.web.id/` melalui browser privat. Harus muncul permintaan username/password sebelum editor dapat dibuka.
2. Cek juga `/api/notes` dan `/api/backup/download` tanpa login: harus ditolak/diminta autentikasi.
3. Login, buat satu catatan, tunggu status Tersimpan, lalu reload untuk memeriksa autosave.
4. Jalankan update dan pastikan catatan tetap ada.
5. Pastikan akses `.env`/`.htpasswd` di webroot tidak membuka file. File sebenarnya hanya berada di folder shared di luar webroot.

Konfigurasi lokal `public/.htaccess` tetap memakai `Require local`. Script membentuk htaccess khusus hosting dari `deploy/public.htaccess`; akses lokal tidak diubah.

## Jika deploy gagal

- Jika gagal sebelum maintenance, situs lama tetap berjalan.
- Jika gagal setelah maintenance aktif, script membiarkan situs dalam maintenance agar kode dan database yang belum selesai tidak dipakai. Perbaiki error lalu ulangi action yang sama: `install` untuk pemasangan yang belum selesai, `update` untuk situs terpasang.
- Jika proses mati paksa dan lock tertinggal, pastikan tidak ada proses deploy aktif sebelum menghapus folder kosong `$HOME/browsernote-app/.deploy-lock`.
- Backup webroot berisi front controller yang menunjuk release sebelumnya. Database dibackup melalui API SQLite, termasuk data WAL yang sudah committed. Untuk pemulihan manual, gunakan pasangan backup webroot dan SQLite yang sesuai; jangan menimpa database aktif saat ada penulisan, dan jangan menghapus release lama yang masih dirujuk. Pemulihan database mengembalikan catatan ke waktu snapshot.
- Jangan sekadar menghapus `.browsernote-maintenance` setelah migrasi/publish gagal. Periksa error dan konsistensi release/database dahulu. Script tidak menjalankan rollback database otomatis.

## Referensi

- [CodeIgniter: Deployment](https://codeigniter.com/user_guide/installation/deployment.html)
- [Apache: Authentication and Authorization](https://httpd.apache.org/docs/2.4/howto/auth.html)
