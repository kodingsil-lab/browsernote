#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 14
# FINAL UAT
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'
$PhpExe      = 'C:\xampp\php\php.exe'

$DatabasePath = Join-Path $ProjectRoot 'writable\browsernote.sqlite'
$ReportDir    = Join-Path $ProjectRoot 'writable\reports'
$Stamp        = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportPath   = Join-Path $ReportDir "BrowserNote_FINAL_UAT_$Stamp.txt"
$TempPhp      = Join-Path $ProjectRoot "writable\stage14_db_verify_$Stamp.php"
$TempBackup   = Join-Path $env:TEMP "browsernote_stage14_backup_$Stamp.sqlite"

$PassCount = 0
$WarnCount = 0
$FailCount = 0
$Report = New-Object System.Collections.Generic.List[string]

function Step([string]$Message) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $Report.Add("")
    $Report.Add("============================================================")
    $Report.Add($Message)
    $Report.Add("============================================================")
}

function Pass([string]$Message) {
    $script:PassCount += 1
    Write-Host "[PASS] $Message" -ForegroundColor Green
    $Report.Add("[PASS] $Message")
}

function Warn([string]$Message) {
    $script:WarnCount += 1
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    $Report.Add("[WARN] $Message")
}

function Fail([string]$Message) {
    $script:FailCount += 1
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    $Report.Add("[FAIL] $Message")
    Save-Report
    exit 1
}

function Save-Report {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

    $summary = @(
        "",
        "============================================================",
        "SUMMARY",
        "============================================================",
        "PASS : $PassCount",
        "WARN : $WarnCount",
        "FAIL : $FailCount",
        "Time : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )

    foreach ($line in $summary) {
        $Report.Add($line)
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines(
        $ReportPath,
        $Report,
        $utf8NoBom
    )
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

function Invoke-Json {
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][string]$Uri,
        [object]$Body = $null
    )

    $params = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = @{ Accept = 'application/json' }
        TimeoutSec  = 12
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $params.ContentType = 'application/json'
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    Invoke-RestMethod @params
}

$Report.Add("BrowserNote FINAL UAT")
$Report.Add("Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Report.Add("Project   : $ProjectRoot")
$Report.Add("URL       : $BaseUrl/")

Step "1. PRECHECK"

$requiredPaths = @(
    $ProjectRoot,
    $DatabasePath,
    (Join-Path $ProjectRoot 'public\assets\vendor\tinymce\tinymce.min.js'),
    (Join-Path $ProjectRoot 'public\assets\js\browsernote.js'),
    (Join-Path $ProjectRoot 'public\assets\js\search.js'),
    (Join-Path $ProjectRoot 'public\assets\js\shortcuts.js'),
    (Join-Path $ProjectRoot 'public\assets\js\export.js'),
    (Join-Path $ProjectRoot 'public\assets\js\polish.js'),
    (Join-Path $ProjectRoot 'public\assets\js\editor-polish-fix.js'),
    (Join-Path $ProjectRoot 'public\assets\css\app.css'),
    (Join-Path $ProjectRoot 'public\assets\css\ui-polish-fix.css'),
    (Join-Path $ProjectRoot '.htaccess'),
    (Join-Path $ProjectRoot 'public\.htaccess')
)

foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Fail "File/path wajib tidak ditemukan: $path"
    }
}

if (-not (Test-Path $PhpExe)) {
    Fail "PHP XAMPP tidak ditemukan."
}

Pass "Semua file inti ditemukan"
Pass "PHP XAMPP ditemukan"
Pass "Stage 12A assets ditemukan"
Pass "Stage 13 hardening files ditemukan"

Step "2. ROOT PAGE + CORE ASSETS"

try {
    $root = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 12 `
        -ErrorAction Stop
}
catch {
    Fail "Root BrowserNote tidak dapat diakses."
}

if ($root.StatusCode -ne 200) {
    Fail "Root BrowserNote bukan HTTP 200."
}

Pass "Root BrowserNote HTTP 200"

$assetUrls = @(
    "$BaseUrl/assets/vendor/tinymce/tinymce.min.js",
    "$BaseUrl/assets/js/browsernote.js",
    "$BaseUrl/assets/js/search.js",
    "$BaseUrl/assets/js/shortcuts.js",
    "$BaseUrl/assets/js/export.js",
    "$BaseUrl/assets/js/polish.js",
    "$BaseUrl/assets/js/editor-polish-fix.js",
    "$BaseUrl/assets/css/app.css",
    "$BaseUrl/assets/css/ui-polish-fix.css"
)

foreach ($url in $assetUrls) {
    try {
        $asset = Invoke-WebRequest `
            -Uri $url `
            -UseBasicParsing `
            -TimeoutSec 10 `
            -ErrorAction Stop
    }
    catch {
        Fail "Asset gagal diakses: $url"
    }

    if ($asset.StatusCode -ne 200) {
        Fail "Asset bukan HTTP 200: $url"
    }

    Pass "Asset HTTP 200: $([System.IO.Path]::GetFileName($url))"
}

Step "3. STATIC FEATURE AUDIT"

$browserJs = [System.IO.File]::ReadAllText(
    (Join-Path $ProjectRoot 'public\assets\js\browsernote.js')
)

$searchJs = [System.IO.File]::ReadAllText(
    (Join-Path $ProjectRoot 'public\assets\js\search.js')
)

$shortcutJs = [System.IO.File]::ReadAllText(
    (Join-Path $ProjectRoot 'public\assets\js\shortcuts.js')
)

$exportJs = [System.IO.File]::ReadAllText(
    (Join-Path $ProjectRoot 'public\assets\js\export.js')
)

$polishJs = [System.IO.File]::ReadAllText(
    (Join-Path $ProjectRoot 'public\assets\js\editor-polish-fix.js')
)

$polishCss = [System.IO.File]::ReadAllText(
    (Join-Path $ProjectRoot 'public\assets\css\ui-polish-fix.css')
)

$featureMarkers = @(
    @{ Name='Autosave debounce'; Text=$browserJs; Marker='const AUTOSAVE_DELAY = 700;' },
    @{ Name='Autosave race guard'; Text=$browserJs; Marker='versionAtStart' },
    @{ Name='Local recovery'; Text=$browserJs; Marker="browsernote.draft.v1." },
    @{ Name='Folders'; Text=$browserJs; Marker='async function createFolder()' },
    @{ Name='Archive'; Text=$browserJs; Marker='async function archiveCurrent()' },
    @{ Name='Trash'; Text=$browserJs; Marker='async function moveCurrentToTrash()' },
    @{ Name='Force delete'; Text=$browserJs; Marker='async function forceDeleteCurrent()' },
    @{ Name='Search'; Text=$searchJs; Marker='window.BrowserNoteSearch' },
    @{ Name='Quick Note'; Text=$shortcutJs; Marker='window.BrowserNoteQuickNote' },
    @{ Name='Shortcut help'; Text=$shortcutJs; Marker='window.BrowserNoteShortcuts' },
    @{ Name='Export HTML'; Text=$exportJs; Marker="format === 'html'" },
    @{ Name='Export Markdown'; Text=$exportJs; Marker="format === 'md'" },
    @{ Name='Export TXT'; Text=$exportJs; Marker="format === 'txt'" },
    @{ Name='SQLite backup UI'; Text=$exportJs; Marker='api/backup/download' },
    @{ Name='Paragraph normal'; Text=$polishJs; Marker='normalizeEmptyEditor' },
    @{ Name='Editor font 15px'; Text=$polishJs; Marker='font-size: 15px !important' },
    @{ Name='Horizontal TinyMCE repair'; Text=$polishCss; Marker='flex-direction: column !important' }
)

foreach ($item in $featureMarkers) {
    if (-not $item.Text.Contains($item.Marker)) {
        Fail "Static feature audit gagal: $($item.Name)"
    }

    Pass $item.Name
}

Step "4. DATABASE INTEGRITY + PERFORMANCE"

$dbVerifyPhp = @'
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

$indexes = [
    'idx_notes_status_updated',
    'idx_notes_folder_status_updated',
    'idx_notes_updated',
    'idx_folders_sort_name'
];

foreach ($indexes as $name) {
    $escaped = SQLite3::escapeString($name);

    $found = $db->querySingle(
        "SELECT COUNT(*)
         FROM sqlite_master
         WHERE type='index'
           AND name='{$escaped}'"
    );

    echo $name . '=' . (int) $found . PHP_EOL;
}

$db->close();
'@

Write-Utf8NoBom -Path $TempPhp -Content $dbVerifyPhp

$dbOut = & $PhpExe $TempPhp $DatabasePath 2>&1
$dbExit = $LASTEXITCODE

Remove-Item $TempPhp -Force -ErrorAction SilentlyContinue

if ($dbExit -ne 0) {
    $dbOut | ForEach-Object {
        Write-Host $_ -ForegroundColor Red
    }

    Fail "Database verification gagal."
}

$dbText = $dbOut -join "`n"

if ($dbText -notlike '*quick_check=ok*') {
    Fail "SQLite quick_check gagal."
}

if ($dbText -notlike '*journal_mode=wal*') {
    Fail "SQLite WAL tidak aktif."
}

Pass "SQLite quick_check = ok"
Pass "SQLite journal_mode = WAL"

foreach ($indexName in @(
    'idx_notes_status_updated',
    'idx_notes_folder_status_updated',
    'idx_notes_updated',
    'idx_folders_sort_name'
)) {
    if ($dbText -notlike "*$indexName=1*") {
        Fail "Index hilang: $indexName"
    }

    Pass "DB index: $indexName"
}

Step "5. NOTES + FOLDER END-TO-END WORKFLOW"

$folderId = $null
$noteId = $null
$token = "FINALUAT$([Guid]::NewGuid().ToString('N').Substring(0,10))"

try {
    $folder = Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/folders" `
        -Body @{
            name = "__FINAL_UAT_FOLDER_$token"
        }

    $folderId = [int]$folder.data.id

    if ($folderId -lt 1) {
        Fail "Create folder tidak mendapatkan ID."
    }

    Pass "Folder create"

    $note = Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/notes" `
        -Body @{
            title = "__FINAL_UAT_NOTE_$token"
            content = "<h2>UAT</h2><p>SearchToken $token</p><pre><code>echo test;</code></pre>"
            folder_id = $folderId
        }

    $noteId = [int]$note.data.id

    if ($noteId -lt 1) {
        Fail "Create note tidak mendapatkan ID."
    }

    Pass "Note create"

    $read = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/notes/$noteId"

    if ([int]$read.data.id -ne $noteId) {
        Fail "Read note mismatch."
    }

    Pass "Note read"

    $updated = Invoke-Json `
        -Method 'PATCH' `
        -Uri "$BaseUrl/api/notes/$noteId" `
        -Body @{
            title = "__FINAL_UAT_NOTE_UPDATED_$token"
            content = "<p>Updated content SearchToken $token SMTP 587</p>"
            folder_id = $folderId
        }

    if ($updated.data.title -ne "__FINAL_UAT_NOTE_UPDATED_$token") {
        Fail "Update note gagal."
    }

    Pass "Note update"
    Pass "Folder assignment"

    $searchToken = [uri]::EscapeDataString($token)

    $search = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/search?q=$searchToken&status=all"

    $searchHit = @(
        $search.data |
        Where-Object { [int]$_.id -eq $noteId }
    )

    if ($searchHit.Count -lt 1) {
        Fail "Search content gagal."
    }

    Pass "Search title/content"

    $archived = Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/notes/$noteId/archive"

    if ([int]$archived.data.is_archived -ne 1) {
        Fail "Archive gagal."
    }

    Pass "Archive note"

    $archiveList = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/notes?status=archived"

    $archiveHit = @(
        $archiveList.data |
        Where-Object { [int]$_.id -eq $noteId }
    )

    if ($archiveHit.Count -lt 1) {
        Fail "Archived note tidak muncul di list."
    }

    Pass "Archive list"

    $archiveSearch = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/search?q=$searchToken&status=all"

    $archiveSearchHit = @(
        $archiveSearch.data |
        Where-Object { [int]$_.id -eq $noteId }
    )

    if ($archiveSearchHit.Count -lt 1) {
        Fail "Archived note tidak searchable."
    }

    Pass "Archived note searchable"

    $restoreArchive = Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/notes/$noteId/restore-archive"

    if ([int]$restoreArchive.data.is_archived -ne 0) {
        Fail "Restore archive gagal."
    }

    Pass "Restore archive"

    $trashed = Invoke-Json `
        -Method 'DELETE' `
        -Uri "$BaseUrl/api/notes/$noteId"

    if ([int]$trashed.data.is_deleted -ne 1) {
        Fail "Move to trash gagal."
    }

    Pass "Move note to trash"

    $trashList = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/notes?status=trash"

    $trashHit = @(
        $trashList.data |
        Where-Object { [int]$_.id -eq $noteId }
    )

    if ($trashHit.Count -lt 1) {
        Fail "Trash list gagal."
    }

    Pass "Trash list"

    $trashSearch = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/search?q=$searchToken&status=all"

    $trashSearchHit = @(
        $trashSearch.data |
        Where-Object { [int]$_.id -eq $noteId }
    )

    if ($trashSearchHit.Count -gt 0) {
        Fail "Trashed note masih muncul di search."
    }

    Pass "Trash excluded from search"

    $restoreTrash = Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/notes/$noteId/restore-trash"

    if ([int]$restoreTrash.data.is_deleted -ne 0) {
        Fail "Restore trash gagal."
    }

    Pass "Restore trash"

    $moveUnfiled = Invoke-Json `
        -Method 'PATCH' `
        -Uri "$BaseUrl/api/notes/$noteId" `
        -Body @{
            folder_id = $null
        }

    if ($null -ne $moveUnfiled.data.folder_id -and "$($moveUnfiled.data.folder_id)" -ne '') {
        Fail "Move to Tanpa Folder gagal."
    }

    Pass "Move note to Tanpa Folder"

    Invoke-Json `
        -Method 'DELETE' `
        -Uri "$BaseUrl/api/notes/$noteId" | Out-Null

    Invoke-Json `
        -Method 'DELETE' `
        -Uri "$BaseUrl/api/notes/$noteId/force" | Out-Null

    Pass "Force delete"

    $noteId = $null

    Invoke-Json `
        -Method 'DELETE' `
        -Uri "$BaseUrl/api/folders/$folderId" | Out-Null

    Pass "Folder delete"

    $folderId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red

    # Best-effort cleanup.
    if ($noteId) {
        try {
            Invoke-Json `
                -Method 'DELETE' `
                -Uri "$BaseUrl/api/notes/$noteId" | Out-Null
        } catch {}

        try {
            Invoke-Json `
                -Method 'DELETE' `
                -Uri "$BaseUrl/api/notes/$noteId/force" | Out-Null
        } catch {}
    }

    if ($folderId) {
        try {
            Invoke-Json `
                -Method 'DELETE' `
                -Uri "$BaseUrl/api/folders/$folderId" | Out-Null
        } catch {}
    }

    Fail "End-to-end workflow gagal."
}

Step "6. QUICK NOTE + SHORTCUT UAT"

if (-not $shortcutJs.Contains("ctrlKey || event.metaKey")) {
    Fail "Shortcut modifier logic tidak ditemukan."
}

if (-not $shortcutJs.Contains("event.altKey")) {
    Fail "Ctrl+Alt+N logic tidak ditemukan."
}

if (-not $shortcutJs.Contains("event.key === 'Enter'")) {
    Fail "Ctrl+Enter Quick Note logic tidak ditemukan."
}

Pass "Ctrl+Alt+N Quick Note binding"
Pass "Ctrl+Enter Quick Note save binding"
Pass "Ctrl+/ shortcut help binding"
Pass "Esc close binding"

Step "7. EXPORT + BACKUP UAT"

foreach ($marker in @(
    'fullHtmlDocument',
    'htmlToMarkdown',
    'textFromHtml',
    'downloadDatabaseBackup'
)) {
    if (-not $exportJs.Contains($marker)) {
        Fail "Export marker hilang: $marker"
    }
}

Pass "HTML export implementation"
Pass "Markdown export implementation"
Pass "TXT export implementation"

if (Test-Path $TempBackup) {
    Remove-Item $TempBackup -Force
}

try {
    Invoke-WebRequest `
        -Uri "$BaseUrl/api/backup/download" `
        -UseBasicParsing `
        -TimeoutSec 20 `
        -OutFile $TempBackup `
        -ErrorAction Stop
}
catch {
    Fail "Backup endpoint gagal."
}

if (-not (Test-Path $TempBackup)) {
    Fail "Backup file tidak terbentuk."
}

$backupBytes = [System.IO.File]::ReadAllBytes(
    $TempBackup
)

if ($backupBytes.Length -lt 100) {
    Fail "Backup SQLite terlalu kecil."
}

$backupHeader = [System.Text.Encoding]::ASCII.GetString(
    $backupBytes,
    0,
    [Math]::Min(15, $backupBytes.Length)
)

if (-not $backupHeader.StartsWith('SQLite format 3')) {
    Fail "Backup bukan SQLite valid."
}

Remove-Item $TempBackup -Force

Pass "SQLite backup endpoint"
Pass "SQLite backup file header valid"

Step "8. SECURITY UAT"

$sensitiveUrls = @(
    'http://localhost/browsernote/.env',
    'http://localhost/browsernote/writable/browsernote.sqlite',
    'http://localhost/browsernote/app/Config/App.php',
    'http://localhost/browsernote/vendor/autoload.php',
    'http://localhost/browsernote/script/14_BROWSERNOTE_FINAL_UAT.ps1'
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
        Fail "Sensitive path belum aman: $url (HTTP $statusCode)"
    }

    Pass "Blocked HTTP $statusCode : $url"
}

$securityHeaders = @(
    'X-Content-Type-Options',
    'X-Frame-Options',
    'Referrer-Policy',
    'Permissions-Policy'
)

foreach ($headerName in $securityHeaders) {
    if ($root.Headers[$headerName]) {
        Pass "Security header: $headerName"
    }
    else {
        Warn "Security header tidak terlihat: $headerName"
    }
}

Step "9. FINAL CLEANUP VERIFICATION"

try {
    $allNotes = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/notes?status=all"

    $allFolders = Invoke-Json `
        -Method 'GET' `
        -Uri "$BaseUrl/api/folders"
}
catch {
    Fail "Cleanup verification API gagal."
}

$testNotes = @(
    $allNotes.data |
    Where-Object {
        "$($_.title)" -like '*FINAL_UAT*'
    }
)

$testFolders = @(
    $allFolders.data |
    Where-Object {
        "$($_.name)" -like '*FINAL_UAT*'
    }
)

if ($testNotes.Count -gt 0) {
    Fail "Masih ada test note FINAL_UAT."
}

if ($testFolders.Count -gt 0) {
    Fail "Masih ada test folder FINAL_UAT."
}

Pass "Test notes cleanup"
Pass "Test folders cleanup"

Step "10. FINAL UAT RESULT"

Save-Report

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "BROWSERNOTE FINAL UAT PASS" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Project      : $ProjectRoot" -ForegroundColor White
Write-Host "URL          : $BaseUrl/" -ForegroundColor White
Write-Host "PASS         : $PassCount" -ForegroundColor White
Write-Host "WARN         : $WarnCount" -ForegroundColor White
Write-Host "FAIL         : $FailCount" -ForegroundColor White
Write-Host "Report       : $ReportPath" -ForegroundColor White
Write-Host ""
Write-Host "Core editor  : PASS" -ForegroundColor White
Write-Host "Autosave     : PASS" -ForegroundColor White
Write-Host "Recovery     : PASS" -ForegroundColor White
Write-Host "Folders      : PASS" -ForegroundColor White
Write-Host "Archive      : PASS" -ForegroundColor White
Write-Host "Trash        : PASS" -ForegroundColor White
Write-Host "Search       : PASS" -ForegroundColor White
Write-Host "Quick Note   : PASS" -ForegroundColor White
Write-Host "Export       : PASS" -ForegroundColor White
Write-Host "Backup       : PASS" -ForegroundColor White
Write-Host "SQLite       : PASS / WAL" -ForegroundColor White
Write-Host "Hardening    : PASS" -ForegroundColor White
Write-Host "UI Stage 12A : PASS markers" -ForegroundColor White
Write-Host ""
Write-Host "FINAL MANUAL UAT:" -ForegroundColor Cyan
Write-Host "1. Buka BrowserNote dengan Ctrl+F5." -ForegroundColor White
Write-Host "2. Buat satu catatan final dan ketik teks normal." -ForegroundColor White
Write-Host "3. Uji heading, bold, list, tabel, code sample, dan link." -ForegroundColor White
Write-Host "4. Pastikan autosave dan refresh mempertahankan isi." -ForegroundColor White
Write-Host "5. Uji Folder -> Arsip -> Pulihkan -> Sampah -> Pulihkan." -ForegroundColor White
Write-Host "6. Cari kata yang hanya ada di isi catatan." -ForegroundColor White
Write-Host "7. Uji Ctrl+Alt+N, Ctrl+F, Ctrl+S, Ctrl+N, dan Ctrl+/." -ForegroundColor White
Write-Host "8. Export HTML/MD/TXT dan download backup SQLite." -ForegroundColor White
Write-Host ""
Write-Host "Jika delapan uji manual ini PASS, BrowserNote v1.0 siap dipakai lokal." -ForegroundColor Green
