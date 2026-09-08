#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 13A
# RESUME HARDENING AFTER SQLITE STEP
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot    = 'C:\xampp\htdocs\browsernote'
$BaseUrl        = 'http://localhost/browsernote/public'
$RootHtaccess   = Join-Path $ProjectRoot '.htaccess'
$PublicHtaccess = Join-Path $ProjectRoot 'public\.htaccess'
$DatabasePath   = Join-Path $ProjectRoot 'writable\browsernote.sqlite'
$PhpExe         = 'C:\xampp\php\php.exe'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage13a_$Stamp"
$TempPhp     = Join-Path $ProjectRoot "writable\stage13a_verify_$Stamp.php"

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
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content
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

    if ([string]::IsNullOrWhiteSpace($relative)) {
        $relative = Split-Path $Path -Leaf
    }

    $destination = Join-Path $BackupDir $relative
    $destinationDir = Split-Path $destination -Parent

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item $Path $destination -Force
}

function Remove-MarkerBlock {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory=$true)][string]$StartMarker,
        [Parameter(Mandatory=$true)][string]$EndMarker
    )

    if ([string]::IsNullOrEmpty($Content)) {
        return ''
    }

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
    $PublicHtaccess,
    $DatabasePath
)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

if (-not (Test-Path $PhpExe)) {
    Fail "PHP tidak ditemukan: $PhpExe"
}

$stage12Fix = Join-Path $ProjectRoot 'public\assets\css\ui-polish-fix.css'

if (-not (Test-Path $stage12Fix)) {
    Fail "Stage 12A belum terdeteksi."
}

Ok "Project ditemukan"
Ok "Stage 12A terverifikasi"
Ok "Database ditemukan"
Ok "Public .htaccess ditemukan"

Step "2. VERIFY SQLITE STEP FROM STAGE 13"

$verifyDbPhp = @'
<?php

$dbPath = $argv[1] ?? '';

if ($dbPath === '' || !is_file($dbPath)) {
    fwrite(STDERR, "database_missing\n");
    exit(2);
}

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
        (string) $db->querySingle('PRAGMA journal_mode')
    ) .
    PHP_EOL;

$required = [
    'idx_notes_status_updated',
    'idx_notes_folder_status_updated',
    'idx_notes_updated',
    'idx_folders_sort_name'
];

foreach ($required as $name) {
    $escaped = SQLite3::escapeString($name);

    $found = $db->querySingle(
        "SELECT COUNT(*)
         FROM sqlite_master
         WHERE type='index'
           AND name='{$escaped}'"
    );

    echo $name . '=' . ((int) $found) . PHP_EOL;
}

$db->close();
'@

Write-Utf8NoBom -Path $TempPhp -Content $verifyDbPhp

$dbOut = & $PhpExe $TempPhp $DatabasePath 2>&1
$dbExit = $LASTEXITCODE

Remove-Item $TempPhp -Force -ErrorAction SilentlyContinue

if ($dbExit -ne 0) {
    $dbOut | ForEach-Object {
        Write-Host $_ -ForegroundColor Red
    }

    Fail "Verifikasi SQLite gagal."
}

$dbText = $dbOut -join "`n"

if ($dbText -notlike '*quick_check=ok*') {
    Fail "SQLite quick_check bukan ok."
}

if ($dbText -notlike '*journal_mode=wal*') {
    Fail "SQLite WAL belum aktif."
}

foreach ($indexName in @(
    'idx_notes_status_updated',
    'idx_notes_folder_status_updated',
    'idx_notes_updated',
    'idx_folders_sort_name'
)) {
    if ($dbText -notlike "*$indexName=1*") {
        Fail "Index Stage 13 belum tersedia: $indexName"
    }

    Ok "Verified: $indexName"
}

Ok "SQLite Stage 13 sudah PASS"
Ok "Tidak mengulang optimasi database"

Step "3. BACKUP HARDENING TARGETS"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $RootHtaccess,
    $PublicHtaccess
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

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

    # Block framework source, database, backups, scripts and dependencies.
    RewriteRule ^(?:app|system|writable|tests|vendor|script)(?:/|$) - [F,L,NC]

    # Block environment and project metadata.
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

if (-not (Test-Path $RootHtaccess)) {
    Fail "Root .htaccess gagal dibuat."
}

Ok "Root .htaccess dibuat/diperbarui"
Ok "Sensitive project paths diblokir"

Step "5. HARDEN PUBLIC APACHE"

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
# Keep access restricted to this machine.
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

Ok "Localhost-only rule dipasang"
Ok "Security headers dikonfigurasi"
Ok "Static cache dikonfigurasi"
Ok "Compression dikonfigurasi"

Step "6. ROOT + API SMOKE TEST"

try {
    $rootResponse = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 10 `
        -ErrorAction Stop

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

Step "7. VERIFY SENSITIVE PATHS BLOCKED"

$sensitiveUrls = @(
    'http://localhost/browsernote/.env',
    'http://localhost/browsernote/writable/browsernote.sqlite',
    'http://localhost/browsernote/app/Config/App.php',
    'http://localhost/browsernote/vendor/autoload.php',
    'http://localhost/browsernote/script/12A_BROWSERNOTE_FIX_UI_TOOLBAR.ps1'
)

foreach ($url in $sensitiveUrls) {
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

    if ($statusCode -ne 403 -and $statusCode -ne 404) {
        Fail "Sensitive URL belum diblokir: $url (HTTP $statusCode)"
    }

    Ok "Blocked HTTP $statusCode : $url"
}

Step "8. VERIFY SECURITY HEADERS"

$expectedHeaders = @(
    'X-Content-Type-Options',
    'X-Frame-Options',
    'Referrer-Policy',
    'Permissions-Policy'
)

$missingHeaders = @()

foreach ($headerName in $expectedHeaders) {
    if (-not $rootResponse.Headers[$headerName]) {
        $missingHeaders += $headerName
    }
}

if ($missingHeaders.Count -eq 0) {
    Ok "Security headers PASS"
}
else {
    Warn (
        "Security headers PARTIAL: " +
        ($missingHeaders -join ', ')
    )

    Warn "Ini biasanya berarti mod_headers Apache belum aktif. Tidak mengganggu fungsi BrowserNote."
}

Step "9. VERIFY STATIC ASSETS"

try {
    $assetResponse = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/browsernote.js" `
        -UseBasicParsing `
        -TimeoutSec 8 `
        -ErrorAction Stop
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
    Warn "Cache-Control belum terlihat. mod_headers mungkin belum aktif."
}

Step "10. FINAL SQLITE CHECK"

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
        (string) $db->querySingle('PRAGMA journal_mode')
    ) .
    PHP_EOL;

$db->close();
'@

Write-Utf8NoBom -Path $TempPhp -Content $finalPhp

$finalOut = & $PhpExe $TempPhp $DatabasePath 2>&1
$finalExit = $LASTEXITCODE

Remove-Item $TempPhp -Force -ErrorAction SilentlyContinue

if ($finalExit -ne 0) {
    $finalOut | ForEach-Object {
        Write-Host $_ -ForegroundColor Red
    }

    Fail "Final SQLite verification gagal."
}

$finalText = $finalOut -join "`n"

if ($finalText -notlike '*quick_check=ok*') {
    Fail "Final SQLite integrity gagal."
}

if ($finalText -notlike '*journal_mode=wal*') {
    Fail "Final SQLite WAL verification gagal."
}

Ok "Final SQLite integrity PASS"
Ok "Final SQLite WAL PASS"

Step "STAGE 13A PASS - STAGE 13 COMPLETE"

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
    Write-Host "Security headers: PARTIAL" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Uji manual Stage 13:" -ForegroundColor Green
Write-Host "1. Buka BrowserNote." -ForegroundColor White
Write-Host "2. Pastikan UI Stage 12A tidak berubah." -ForegroundColor White
Write-Host "3. Uji autosave, Search, Quick Note, Folder, Arsip, dan Sampah." -ForegroundColor White
Write-Host "4. Uji Export / Backup." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 14 - Final UAT" -ForegroundColor Green
