#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 13
# PERFORMANCE + HARDENING
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot    = 'C:\xampp\htdocs\browsernote'
$BaseUrl        = 'http://localhost/browsernote/public'
$RootHtaccess   = Join-Path $ProjectRoot '.htaccess'
$PublicHtaccess = Join-Path $ProjectRoot 'public\.htaccess'
$DatabasePath   = Join-Path $ProjectRoot 'writable\browsernote.sqlite'
$PhpExe         = 'C:\xampp\php\php.exe'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage13_$Stamp"
$TempPhp     = Join-Path $ProjectRoot "writable\stage13_db_optimize_$Stamp.php"

function Step([string]$Message) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    $parent = Split-Path $Path -Parent

    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Backup-File {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    $relative = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $destination = Join-Path $BackupDir $relative
    $destinationDir = Split-Path $destination -Parent

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item $Path $destination -Force
}

function Remove-MarkerBlock {
    param(
        [Parameter(Mandatory=$true)][string]$Content,
        [Parameter(Mandatory=$true)][string]$StartMarker,
        [Parameter(Mandatory=$true)][string]$EndMarker
    )

    $pattern = '(?s)\r?\n?' +
        [regex]::Escape($StartMarker) +
        '.*?' +
        [regex]::Escape($EndMarker) +
        '\r?\n?'

    return [regex]::Replace(
        $Content,
        $pattern,
        "`r`n"
    )
}

Step "1. PRECHECK"

foreach ($path in @(
    $ProjectRoot,
    $DatabasePath,
    $PublicHtaccess
)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

if (-not (Test-Path $PhpExe)) {
    Fail "PHP XAMPP tidak ditemukan: $PhpExe"
}

$stage12Fix = Join-Path $ProjectRoot 'public\assets\css\ui-polish-fix.css'

if (-not (Test-Path $stage12Fix)) {
    Fail "Stage 12A belum terdeteksi."
}

Ok "Project ditemukan"
Ok "Stage 12A terverifikasi"
Ok "Database ditemukan"
Ok "PHP ditemukan: $PhpExe"

Step "2. BACKUP HARDENING TARGETS"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $RootHtaccess,
    $PublicHtaccess,
    $DatabasePath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. SQLITE INTEGRITY + WAL + INDEXES"

$dbOptimizePhp = @'
<?php

$dbPath = $argv[1] ?? '';

if ($dbPath === '' || !is_file($dbPath)) {
    fwrite(STDERR, "database_missing\n");
    exit(2);
}

if (!class_exists('SQLite3')) {
    fwrite(STDERR, "sqlite3_extension_missing\n");
    exit(3);
}

$db = new SQLite3(
    $dbPath,
    SQLITE3_OPEN_READWRITE
);

$db->busyTimeout(5000);

$quickCheck = $db->querySingle('PRAGMA quick_check');

if ($quickCheck !== 'ok') {
    fwrite(STDERR, "quick_check=" . $quickCheck . "\n");
    $db->close();
    exit(4);
}

$journalMode = $db->querySingle('PRAGMA journal_mode=WAL');

if (strtolower((string) $journalMode) !== 'wal') {
    fwrite(STDERR, "journal_mode=" . $journalMode . "\n");
    $db->close();
    exit(5);
}

$statements = [
    'CREATE INDEX IF NOT EXISTS idx_notes_status_updated
        ON notes(is_deleted, is_archived, updated_at DESC)',

    'CREATE INDEX IF NOT EXISTS idx_notes_folder_status_updated
        ON notes(folder_id, is_deleted, is_archived, updated_at DESC)',

    'CREATE INDEX IF NOT EXISTS idx_notes_updated
        ON notes(updated_at DESC)',

    'CREATE INDEX IF NOT EXISTS idx_folders_sort_name
        ON folders(sort_order, name)'
];

foreach ($statements as $sql) {
    if (!$db->exec($sql)) {
        fwrite(
            STDERR,
            "index_error=" . $db->lastErrorMsg() . "\n"
        );

        $db->close();
        exit(6);
    }
}

$indexes = [];

$result = $db->query(
    "SELECT name
     FROM sqlite_master
     WHERE type = 'index'
       AND name LIKE 'idx_%'
     ORDER BY name"
);

while ($row = $result->fetchArray(SQLITE3_ASSOC)) {
    $indexes[] = $row['name'];
}

$finalCheck = $db->querySingle('PRAGMA quick_check');

if ($finalCheck !== 'ok') {
    fwrite(STDERR, "final_quick_check=" . $finalCheck . "\n");
    $db->close();
    exit(7);
}

echo "quick_check=ok\n";
echo "journal_mode=wal\n";
echo "indexes=" . implode(',', $indexes) . "\n";

$db->close();
'@

Write-Utf8NoBom -Path $TempPhp -Content $dbOptimizePhp

$dbOutput = & $PhpExe $TempPhp $DatabasePath 2>&1
$dbExit = $LASTEXITCODE

Remove-Item $TempPhp -Force -ErrorAction SilentlyContinue

if ($dbExit -ne 0) {
    $dbOutput | ForEach-Object {
        Write-Host $_ -ForegroundColor Red
    }

    Fail "Optimasi SQLite gagal."
}

$dbText = $dbOutput -join "`n"

if ($dbText -notlike '*quick_check=ok*') {
    Fail "SQLite quick_check tidak PASS."
}

if ($dbText -notlike '*journal_mode=wal*') {
    Fail "SQLite WAL tidak aktif."
}

foreach ($indexName in @(
    'idx_notes_status_updated',
    'idx_notes_folder_status_updated',
    'idx_notes_updated',
    'idx_folders_sort_name'
)) {
    if ($dbText -notlike "*$indexName*") {
        Fail "Index tidak ditemukan: $indexName"
    }

    Ok "Index: $indexName"
}

Ok "SQLite quick_check PASS"
Ok "SQLite WAL mode PASS"

Step "4. PROTECT PROJECT ROOT"

$rootContent = ''

if (Test-Path $RootHtaccess) {
    $rootContent = [System.IO.File]::ReadAllText(
        $RootHtaccess
    )
}

$rootStart = '# <BROWSERNOTE_STAGE13_ROOT_HARDENING>'
$rootEnd   = '# </BROWSERNOTE_STAGE13_ROOT_HARDENING>'

$rootContent = Remove-MarkerBlock `
    -Content $rootContent `
    -StartMarker $rootStart `
    -EndMarker $rootEnd

$rootBlock = @'
# <BROWSERNOTE_STAGE13_ROOT_HARDENING>

<IfModule mod_rewrite.c>
    RewriteEngine On

    # Block framework source, database, backups, scripts and dependencies
    # from direct HTTP access through htdocs.
    RewriteRule ^(?:app|system|writable|tests|vendor|script)(?:/|$) - [F,L,NC]

    # Block project metadata and environment files.
    RewriteRule ^(?:\.env|composer\.(?:json|lock)|phpunit\.xml(?:\.dist)?|spark)$ - [F,L,NC]
</IfModule>

<FilesMatch "^\.">
    Require all denied
</FilesMatch>

# </BROWSERNOTE_STAGE13_ROOT_HARDENING>
'@

$rootCombined = $rootContent.TrimEnd()

if ($rootCombined -ne '') {
    $rootCombined += "`r`n`r`n"
}

$rootCombined += $rootBlock.Replace("`n", "`r`n").Trim()
$rootCombined += "`r`n"

Write-Utf8NoBom -Path $RootHtaccess -Content $rootCombined

Ok "Sensitive project paths diblokir"

Step "5. HARDEN PUBLIC APACHE + LOCALHOST ONLY"

$publicContent = [System.IO.File]::ReadAllText(
    $PublicHtaccess
)

$publicStart = '# <BROWSERNOTE_STAGE13_PUBLIC_HARDENING>'
$publicEnd   = '# </BROWSERNOTE_STAGE13_PUBLIC_HARDENING>'

$publicContent = Remove-MarkerBlock `
    -Content $publicContent `
    -StartMarker $publicStart `
    -EndMarker $publicEnd

$publicBlock = @'
# <BROWSERNOTE_STAGE13_PUBLIC_HARDENING>

# BrowserNote has no authentication yet.
# Keep the application accessible from this machine only.
<IfModule mod_authz_core.c>
    Require local
</IfModule>

<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "same-origin"
    Header always set Permissions-Policy "camera=(), microphone=(), geolocation=()"

    <FilesMatch "\.(?:css|js|png|jpg|jpeg|gif|svg|webp|ico)$">
        Header set Cache-Control "public, max-age=300"
    </FilesMatch>
</IfModule>

<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE text/javascript
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/json
    AddOutputFilterByType DEFLATE image/svg+xml
</IfModule>

# </BROWSERNOTE_STAGE13_PUBLIC_HARDENING>
'@

$publicCombined = $publicContent.TrimEnd()

if ($publicCombined -ne '') {
    $publicCombined += "`r`n`r`n"
}

$publicCombined += $publicBlock.Replace("`n", "`r`n").Trim()
$publicCombined += "`r`n"

Write-Utf8NoBom -Path $PublicHtaccess -Content $publicCombined

Ok "Localhost-only access dipasang"
Ok "Security headers dikonfigurasi"
Ok "Static cache 300 detik dikonfigurasi"
Ok "Compression dikonfigurasi jika mod_deflate tersedia"

Step "6. ROOT + API SMOKE TEST"

try {
    $rootResponse = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 10

    $notesResponse = Invoke-RestMethod `
        -Method GET `
        -Uri "$BaseUrl/api/notes?status=active" `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 10 `
        -ErrorAction Stop

    $searchResponse = Invoke-RestMethod `
        -Method GET `
        -Uri "$BaseUrl/api/search?q=BrowserNote&status=all" `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 10 `
        -ErrorAction Stop
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Root/API smoke test gagal setelah hardening."
}

if ($rootResponse.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if (-not $notesResponse.ok) {
    Fail "Notes API tidak normal."
}

if (-not $searchResponse.ok) {
    Fail "Search API tidak normal."
}

Ok "Root BrowserNote PASS"
Ok "Notes API PASS"
Ok "Search API PASS"

Step "7. VERIFY SENSITIVE PATHS ARE BLOCKED"

$sensitiveUrls = @(
    'http://localhost/browsernote/.env',
    'http://localhost/browsernote/writable/browsernote.sqlite',
    'http://localhost/browsernote/app/Config/App.php',
    'http://localhost/browsernote/vendor/autoload.php',
    'http://localhost/browsernote/script/12A_BROWSERNOTE_FIX_UI_TOOLBAR.ps1'
)

foreach ($url in $sensitiveUrls) {
    $blocked = $false
    $statusCode = $null

    try {
        $response = Invoke-WebRequest `
            -Uri $url `
            -UseBasicParsing `
            -TimeoutSec 8 `
            -ErrorAction Stop

        $statusCode = [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
    }

    if ($statusCode -eq 403 -or $statusCode -eq 404) {
        $blocked = $true
    }

    if (-not $blocked) {
        Fail "Sensitive URL belum diblokir: $url (HTTP $statusCode)"
    }

    Ok "Blocked: $url"
}

Step "8. VERIFY SECURITY HEADERS"

$headers = $rootResponse.Headers

$expectedHeaders = @(
    'X-Content-Type-Options',
    'X-Frame-Options',
    'Referrer-Policy',
    'Permissions-Policy'
)

$missingHeaders = @()

foreach ($headerName in $expectedHeaders) {
    if (-not $headers[$headerName]) {
        $missingHeaders += $headerName
    }
}

if ($missingHeaders.Count -eq 0) {
    Ok "Security headers PASS"
}
else {
    Warn (
        "Header Apache tidak semuanya aktif: " +
        ($missingHeaders -join ', ')
    )

    Warn "Kemungkinan mod_headers belum aktif. Aplikasi tetap berjalan dan path sensitif sudah diblokir."
}

Step "9. VERIFY STATIC ASSETS"

$assetUrl = "$BaseUrl/assets/js/browsernote.js"

try {
    $assetResponse = Invoke-WebRequest `
        -Uri $assetUrl `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Static asset tidak dapat diakses."
}

if ($assetResponse.StatusCode -ne 200) {
    Fail "browsernote.js tidak HTTP 200."
}

Ok "Static assets PASS"

if ($assetResponse.Headers['Cache-Control']) {
    Ok "Static Cache-Control aktif"
}
else {
    Warn "Cache-Control tidak terlihat pada response. mod_headers mungkin belum aktif."
}

Step "10. FINAL DATABASE CHECK"

$finalPhp = @'
<?php

$dbPath = $argv[1] ?? '';

$db = new SQLite3(
    $dbPath,
    SQLITE3_OPEN_READONLY
);

$db->busyTimeout(5000);

echo "quick_check=" .
    $db->querySingle('PRAGMA quick_check') .
    PHP_EOL;

echo "journal_mode=" .
    strtolower(
        (string) $db->querySingle(
            'PRAGMA journal_mode'
        )
    ) .
    PHP_EOL;

$db->close();
'@

Write-Utf8NoBom -Path $TempPhp -Content $finalPhp

$finalOutput = & $PhpExe $TempPhp $DatabasePath 2>&1
$finalExit = $LASTEXITCODE

Remove-Item $TempPhp -Force -ErrorAction SilentlyContinue

if ($finalExit -ne 0) {
    Fail "Final database check gagal."
}

$finalText = $finalOutput -join "`n"

if ($finalText -notlike '*quick_check=ok*') {
    Fail "Final SQLite quick_check gagal."
}

if ($finalText -notlike '*journal_mode=wal*') {
    Fail "Final SQLite WAL verification gagal."
}

Ok "Final SQLite integrity PASS"

Step "STAGE 13 PASS"

Write-Host ""
Write-Host "Project         : $ProjectRoot" -ForegroundColor White
Write-Host "URL             : $BaseUrl/" -ForegroundColor White
Write-Host "UI              : UNCHANGED" -ForegroundColor White
Write-Host "SQLite integrity: PASS" -ForegroundColor White
Write-Host "SQLite WAL      : ENABLED" -ForegroundColor White
Write-Host "DB indexes      : PASS" -ForegroundColor White
Write-Host "Sensitive paths : BLOCKED" -ForegroundColor White
Write-Host "Localhost only  : ENABLED" -ForegroundColor White
Write-Host "API smoke       : PASS" -ForegroundColor White
Write-Host "Static assets   : PASS" -ForegroundColor White

if ($missingHeaders.Count -eq 0) {
    Write-Host "Security headers: PASS" -ForegroundColor White
}
else {
    Write-Host "Security headers: PARTIAL - Apache mod_headers check recommended" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Catatan penting:" -ForegroundColor Green
Write-Host "BrowserNote sekarang sengaja hanya dapat diakses dari localhost/loopback." -ForegroundColor White
Write-Host "Jika nanti dipasang pada domain/VPS, aturan Require local harus dilepas dan autentikasi harus ditambahkan lebih dahulu." -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 13:" -ForegroundColor Green
Write-Host "1. Buka BrowserNote dan pastikan editor tetap normal." -ForegroundColor White
Write-Host "2. Uji autosave." -ForegroundColor White
Write-Host "3. Uji Search." -ForegroundColor White
Write-Host "4. Uji Quick Note." -ForegroundColor White
Write-Host "5. Uji Export / Backup." -ForegroundColor White
Write-Host "6. Pastikan Folder, Arsip, dan Sampah tetap normal." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 14 - Final UAT" -ForegroundColor Green
