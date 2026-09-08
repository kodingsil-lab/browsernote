<?php
/** CLI-only helpers for a hosting release. Never place this directory in the webroot. */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

function stop(string $message): never
{
    fwrite(STDERR, "BrowserNote: $message\n");
    exit(1);
}
function put(string $path, string $content): void
{
    if (file_put_contents($path, $content) === false) stop("Gagal menulis $path");
}
function checkedPath(string $path): string
{
    if (!preg_match('~^/[a-zA-Z0-9_./-]+$~D', $path) || str_contains($path, '/../')) stop('Path hosting tidak valid.');
    return $path;
}
try {
    $action = $argv[1] ?? '';
    switch ($action) {
        case 'preflight':
            if (PHP_VERSION_ID < 80200) stop('PHP CLI minimal 8.2.');
            foreach (['intl', 'mbstring', 'sqlite3', 'fileinfo', 'openssl'] as $extension) {
                if (!extension_loaded($extension)) stop("Ekstensi PHP belum aktif: $extension");
            }
            echo 'PHP ' . PHP_VERSION . ": ekstensi OK\n";
            break;
        case 'init-env':
            $path = checkedPath($argv[2] ?? '');
            if (is_file($path)) {
                if (filesize($path) === 0) stop('.env hosting kosong. Perbaiki terlebih dahulu.');
                echo ".env hosting dipertahankan.\n";
                break;
            }
            $key = bin2hex(random_bytes(32));
            $content = "CI_ENVIRONMENT = production\napp.baseURL = 'https://note.sil.web.id/'\napp.indexPage = ''\napp.forceGlobalSecureRequests = true\n\ndatabase.default.DBDriver = SQLite3\ndatabase.default.database = browsernote.sqlite\ndatabase.default.DBPrefix = ''\ndatabase.default.DBDebug = false\ndatabase.default.foreignKeys = true\ndatabase.default.busyTimeout = 5000\n\nencryption.key = 'hex2bin:$key'\nlogger.threshold = 3\n";
            $handle = fopen($path, 'x');
            if ($handle === false) stop('Tidak dapat membuat .env baru.');
            chmod($path, 0600);
            if (fwrite($handle, $content) !== strlen($content)) stop('Gagal menulis .env lengkap.');
            fclose($handle);
            break;
        case 'prepare-public':
            $release = checkedPath($argv[2] ?? '');
            $auth = checkedPath($argv[3] ?? '');
            $index = file_get_contents($release . '/public/index.php');
            $needle = "require FCPATH . '../app/Config/Paths.php';";
            if ($index === false || substr_count($index, $needle) !== 1) stop('Format front controller berubah; patch dibatalkan.');
            put($release . '/public/index.php', str_replace($needle, 'require ' . var_export($release . '/app/Config/Paths.php', true) . ';', $index));
            $rules = file_get_contents(__DIR__ . '/public.htaccess');
            if ($rules === false || substr_count($rules, '@@AUTH_FILE@@') !== 1) stop('Template htaccess tidak valid.');
            $rules = str_replace('@@AUTH_FILE@@', $auth, $rules);
            $existingHtaccess = $argv[4] ?? '';
            if ($existingHtaccess !== '' && is_file($existingHtaccess)) {
                $existingHtaccess = checkedPath($existingHtaccess);
                $existingRules = file_get_contents($existingHtaccess);
                if ($existingRules === false) stop('Tidak dapat membaca htaccess cPanel yang ada.');
                preg_match_all(
                    '~^#(?: php --)? BEGIN cPanel-generated[^\r\n]*\R.*?^#(?: php --)? END cPanel-generated[^\r\n]*(?:\R|$)~ms',
                    $existingRules,
                    $managedBlocks,
                );
                if ($managedBlocks[0] !== []) {
                    $rules = rtrim($rules) . "\n\n" . implode("\n", array_map('trim', $managedBlocks[0])) . "\n";
                }
            }
            put($release . '/public/.htaccess', $rules);
            break;
        case 'backup-db':
            $source = checkedPath($argv[2] ?? '');
            $target = checkedPath($argv[3] ?? '');
            if (!is_file($source)) { echo "Install pertama: database akan dibuat melalui migrasi.\n"; break; }
            if (file_exists($target)) stop('Target backup sudah ada.');
            $db = new SQLite3($source, SQLITE3_OPEN_READONLY);
            $db->busyTimeout(5000);
            $backup = new SQLite3($target, SQLITE3_OPEN_READWRITE | SQLITE3_OPEN_CREATE);
            chmod($target, 0600);
            if (!$db->backup($backup) || $backup->querySingle('PRAGMA integrity_check') !== 'ok') stop('Snapshot SQLite gagal diverifikasi.');
            $backup->close();
            $db->close();
            echo "Snapshot SQLite terverifikasi.\n";
            break;
        case 'migrate':
            $release = checkedPath($argv[2] ?? '');
            $expectedDb = checkedPath($argv[3] ?? '');
            define('FCPATH', $release . '/public/');
            define('ENVIRONMENT', 'production');
            require $release . '/app/Config/Paths.php';
            $paths = new Config\Paths();
            require $paths->systemDirectory . '/Boot.php';
            CodeIgniter\Boot::bootConsole($paths);
            $dbConfig = config('Database')->default;
            if ($dbConfig['DBDriver'] !== 'SQLite3' || $dbConfig['database'] !== 'browsernote.sqlite') stop('Database .env harus SQLite3 dengan nama browsernote.sqlite.');
            if (realpath(dirname($expectedDb)) !== realpath(WRITEPATH)) stop('WRITEPATH tidak menunjuk shared writable.');
            $appConfig = config('App');
            if ($appConfig->baseURL !== 'https://note.sil.web.id/' || !$appConfig->forceGlobalSecureRequests) stop('Base URL/HTTPS pada .env hosting tidak sesuai.');
            $migrations = service('migrations');
            $migrations->setNamespace('App');
            if (!$migrations->latest()) stop('Migrasi database gagal.');
            $db = db_connect();
            if (!$db->tableExists('notes') || !$db->tableExists('folders')) stop('Tabel BrowserNote belum lengkap.');
            if (!service('cache')->clean()) stop('Cache hosting gagal dibersihkan.');
            chmod($expectedDb, 0600);
            echo "Migrasi dan pemeriksaan tabel berhasil.\n";
            break;
        default:
            stop('Action helper tidak dikenal.');
    }
} catch (Throwable $error) {
    stop($error->getMessage());
}
