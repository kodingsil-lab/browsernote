#!/usr/bin/env bash
# Run on Linux hosting through SSH / cPanel Terminal, from an uploaded source package.
set -Eeuo pipefail
umask 022
ACTION="${1:-check}"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP_DIR="${APP_DIR:-$HOME/browsernote-app}"
WEB_DIR="${WEB_DIR:-$HOME/note.sil.web.id}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/browsernote-deploy}"
PHP_BIN="${PHP_BIN:-php}"
COMPOSER_BIN="${COMPOSER_BIN:-}"
AUTH_USER="${AUTH_USER:-penulis}"
APP_URL='https://note.sil.web.id/'
LOCK_HELD=0
MAINTENANCE=0
STAMP="$(date +%Y%m%d-%H%M%S)-$$"

log() { printf '\n[BrowserNote] %s\n' "$*"; }
fail() { printf '\n[BrowserNote] ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Command tidak tersedia: $1"; }
cleanup() {
    local code=$?
    if (( LOCK_HELD )); then rmdir -- "$APP_DIR/.deploy-lock" || true; fi
    if (( code != 0 && MAINTENANCE )); then
        printf '\nDeploy gagal; situs tetap maintenance. Backup: %s/%s\nPerbaiki penyebabnya lalu jalankan update kembali.\n' "$BACKUP_DIR" "$STAMP" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$ACTION" in
    check|install|update) ;;
    *) fail 'Usage: bash deploy-cpanel.sh [check|install|update]' ;;
esac
for command in realpath rsync tar find cp mkdir ln mv chmod rmdir rm cat touch; do need "$command"; done
need "$PHP_BIN"
"$PHP_BIN" "$SOURCE_DIR/deploy/hosting.php" preflight
ACCOUNT_ROOT="$(realpath -e -- "$HOME")"
APP_DIR="$(realpath -m -- "$APP_DIR")"
WEB_DIR="$(realpath -m -- "$WEB_DIR")"
BACKUP_DIR="$(realpath -m -- "$BACKUP_DIR")"
for path in "$APP_DIR" "$WEB_DIR" "$BACKUP_DIR"; do
    [[ "$path" == "$ACCOUNT_ROOT/"* ]] || fail "Target harus berupa subfolder home hosting: $path"
    [[ "$path" =~ ^/[a-zA-Z0-9_./-]+$ ]] || fail "Path tidak didukung (gunakan huruf, angka, /, _, -, titik): $path"
done
for private in "$APP_DIR" "$BACKUP_DIR"; do
    [[ "$private" != "$ACCOUNT_ROOT/public_html" && "$private" != "$ACCOUNT_ROOT/public_html/"* ]] || fail 'App dan backup harus di luar public_html.'
done
paths=("$APP_DIR" "$WEB_DIR" "$BACKUP_DIR" "$SOURCE_DIR")
for ((i=0; i<${#paths[@]}; i++)); do
    for ((j=i+1; j<${#paths[@]}; j++)); do
        [[ "${paths[i]}" != "${paths[j]}" && "${paths[i]}" != "${paths[j]}/"* && "${paths[j]}" != "${paths[i]}/"* ]] || fail 'Folder source, aplikasi, webroot, dan backup tidak boleh saling menampung.'
    done
done
[[ ! -L "$APP_DIR/shared" && ! -L "$APP_DIR/releases" && ! -L "$APP_DIR/shared/writable" ]] || fail 'Folder data hosting tidak boleh berupa symlink.'
for file in composer.json composer.lock spark public/index.php public/assets/vendor/tinymce/tinymce.min.js app/Config/Paths.php; do
    [[ -f "$SOURCE_DIR/$file" ]] || fail "Source tidak lengkap: $file"
done
# Reject symlinks in uploaded code so an archive cannot redirect publishing outside its source.
[[ -z "$(find "$SOURCE_DIR/app" "$SOURCE_DIR/public" "$SOURCE_DIR/deploy" -type l -print -quit)" ]] || fail 'Source mengandung symlink.'

if [[ -z "$COMPOSER_BIN" ]]; then
    COMPOSER_BIN="$(command -v composer || true)"
    if [[ -z "$COMPOSER_BIN" ]]; then
        for candidate in /opt/cpanel/composer/bin/composer /usr/local/bin/composer "$HOME/bin/composer.phar"; do
            if [[ -f "$candidate" ]]; then COMPOSER_BIN="$candidate"; break; fi
        done
    fi
fi
[[ -f "$COMPOSER_BIN" ]] || fail 'Composer belum ditemukan. Isi COMPOSER_BIN=/path/ke/composer atau composer.phar.'
"$PHP_BIN" "$COMPOSER_BIN" --version

if [[ -f "$APP_DIR/.browsernote-app" ]]; then
    [[ "$(cat "$APP_DIR/.browsernote-app")" == "$WEB_DIR" ]] || fail 'App ini sudah terhubung ke webroot lain.'
    [[ -f "$WEB_DIR/.browsernote-deployed" ]] || fail 'Marker webroot hilang; periksa target sebelum deploy.'
    [[ "$(cat "$WEB_DIR/.browsernote-deployed")" == "$APP_DIR" ]] || fail 'Webroot dimiliki deployment lain.'
    [[ -s "$APP_DIR/shared/.env" && -s "$APP_DIR/shared/.htpasswd" && -f "$APP_DIR/shared/writable/browsernote.sqlite" ]] || fail 'Data deployment lama tidak lengkap; pulihkan data sebelum update.'
    [[ "$ACTION" != install ]] || fail 'Sudah terpasang. Gunakan update.'
elif [[ -f "$APP_DIR/.browsernote-installing" ]]; then
    [[ "$(cat "$APP_DIR/.browsernote-installing")" == "$WEB_DIR" ]] || fail 'Target install sebelumnya berbeda.'
    [[ "$ACTION" != update ]] || fail 'Install sebelumnya belum selesai. Jalankan install kembali.'
else
    [[ "$ACTION" != update ]] || fail 'Belum terpasang. Gunakan install.'
    [[ ! -d "$APP_DIR" || -z "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail 'App dir tidak kosong dan belum dikenali sebagai BrowserNote.'
    [[ ! -d "$WEB_DIR" || -z "$(find "$WEB_DIR" -mindepth 1 -maxdepth 1 ! -name '.well-known' -print -quit)" ]] || fail 'Webroot harus kosong (boleh .well-known). Pindahkan file bawaan hosting terlebih dahulu.'
fi
if [[ ! -s "$APP_DIR/shared/.htpasswd" ]]; then
    HTPASSWD_BIN="$(command -v htpasswd || true)"
    [[ -n "$HTPASSWD_BIN" ]] || HTPASSWD_BIN='/usr/local/apache/bin/htpasswd'
    [[ -x "$HTPASSWD_BIN" ]] || fail 'htpasswd tidak ditemukan. Minta hosting menyediakan Apache htpasswd.'
    [[ "$AUTH_USER" =~ ^[a-zA-Z0-9_.-]+$ ]] || fail 'AUTH_USER hanya boleh huruf, angka, _, -, titik.'
fi
log "Preflight OK. Domain=$APP_URL App=$APP_DIR Webroot=$WEB_DIR"
if [[ "$ACTION" == check ]]; then
    log 'Tidak ada file hosting yang diubah. Samakan PHP domain dengan PHP CLI dan arahkan document root ke webroot di atas.'
    exit 0
fi

mkdir -p -- "$APP_DIR" "$APP_DIR/releases" "$APP_DIR/shared" "$BACKUP_DIR" "$WEB_DIR"
mkdir -- "$APP_DIR/.deploy-lock" || fail 'Deploy lain sedang berjalan. Jika proses sebelumnya mati, periksa sebelum menghapus .deploy-lock.'
LOCK_HELD=1
if [[ "$ACTION" == install ]]; then printf '%s\n' "$WEB_DIR" > "$APP_DIR/.browsernote-installing"; fi
SHARED="$APP_DIR/shared"
RELEASE="$APP_DIR/releases/$STAMP"
SNAPSHOT="$BACKUP_DIR/$STAMP"
mkdir -- "$RELEASE"
mkdir -p -- "$SNAPSHOT" "$SHARED/writable"
chmod 700 "$BACKUP_DIR" "$SNAPSHOT" "$SHARED/writable"
for directory in cache logs session uploads debugbar backups; do
    mkdir -p -- "$SHARED/writable/$directory"
    chmod 700 "$SHARED/writable/$directory"
done

if [[ ! -s "$SHARED/.htpasswd" ]]; then
    [[ -t 0 ]] || fail 'Install pertama membutuhkan terminal interaktif (gunakan ssh -t) untuk password.'
    log "Buat password situs untuk pengguna $AUTH_USER (input tersembunyi)."
    "$HTPASSWD_BIN" -cB "$SHARED/.htpasswd" "$AUTH_USER"
fi
# Apache reads the password hashes; plaintext secrets and SQLite remain owner-only.
chmod 644 "$SHARED/.htpasswd"
"$PHP_BIN" "$SOURCE_DIR/deploy/hosting.php" init-env "$SHARED/.env"

log 'Menyiapkan release dan dependensi sebelum mengubah situs aktif.'
cp -a -- "$SOURCE_DIR/app" "$SOURCE_DIR/public" "$SOURCE_DIR/deploy" "$RELEASE/"
cp -- "$SOURCE_DIR/composer.json" "$SOURCE_DIR/composer.lock" "$SOURCE_DIR/spark" "$RELEASE/"
ln -s -- "$SHARED/.env" "$RELEASE/.env"
ln -s -- "$SHARED/writable" "$RELEASE/writable"
"$PHP_BIN" "$COMPOSER_BIN" install --working-dir="$RELEASE" --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader --no-scripts --no-plugins
"$PHP_BIN" "$COMPOSER_BIN" check-platform-reqs --working-dir="$RELEASE" --no-dev
"$PHP_BIN" "$SOURCE_DIR/deploy/hosting.php" prepare-public "$RELEASE" "$SHARED/.htpasswd"
"$PHP_BIN" -l "$RELEASE/public/index.php"
find "$RELEASE/app" "$RELEASE/public" "$RELEASE/vendor" "$RELEASE/deploy" -type d -exec chmod 755 {} +
find "$RELEASE/app" "$RELEASE/public" "$RELEASE/vendor" "$RELEASE/deploy" -type f -exec chmod 644 {} +

log 'Membuat backup webroot, konfigurasi, dan snapshot SQLite.'
tar --exclude='./.well-known' --exclude='./.browsernote-maintenance' -czf "$SNAPSHOT/webroot.tar.gz" -C "$WEB_DIR" .
cp -- "$SHARED/.env" "$SNAPSHOT/.env"
cp -- "$SHARED/.htpasswd" "$SNAPSHOT/.htpasswd"
chmod 600 "$SNAPSHOT/.env" "$SNAPSHOT/.htpasswd" "$SNAPSHOT/webroot.tar.gz"
# Both old and new deployment htaccess recognize this marker; preserve it during rsync.
touch "$WEB_DIR/.browsernote-maintenance"
MAINTENANCE=1
if [[ "$ACTION" == install ]]; then cp -- "$RELEASE/public/.htaccess" "$WEB_DIR/.htaccess"; fi
"$PHP_BIN" "$SOURCE_DIR/deploy/hosting.php" backup-db "$SHARED/writable/browsernote.sqlite" "$SNAPSHOT/browsernote.sqlite"
"$PHP_BIN" "$SOURCE_DIR/deploy/hosting.php" migrate "$RELEASE" "$SHARED/writable/browsernote.sqlite"

log 'Menerbitkan hanya public/ ke webroot domain.'
rsync -a --delete --exclude='.well-known/' --exclude='.browsernote-maintenance' --exclude='.browsernote-deployed' --exclude='index.php' "$RELEASE/public/" "$WEB_DIR/"
# Replace the front controller last so it points to the fully prepared release.
cp -- "$RELEASE/public/index.php" "$WEB_DIR/.index-$STAMP.php"
mv -f -- "$WEB_DIR/.index-$STAMP.php" "$WEB_DIR/index.php"
printf '%s\n' "$APP_DIR" > "$WEB_DIR/.browsernote-deployed"
printf '%s\n' "$WEB_DIR" > "$APP_DIR/.browsernote-app"
printf '%s\n' "$RELEASE" > "$APP_DIR/current-release"
if [[ -f "$APP_DIR/.browsernote-installing" ]]; then rm -- "$APP_DIR/.browsernote-installing"; fi
rm -- "$WEB_DIR/.browsernote-maintenance"
MAINTENANCE=0
log "Deploy selesai: $APP_URL"
printf 'Release: %s\nData: %s/writable/browsernote.sqlite\nBackup: %s\n' "$RELEASE" "$SHARED" "$SNAPSHOT"
log 'Uji URL melalui HTTPS: tanpa login harus meminta password; setelah login editor dan autosave harus berfungsi.'
