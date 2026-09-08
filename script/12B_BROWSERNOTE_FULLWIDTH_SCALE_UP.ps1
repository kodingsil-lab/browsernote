#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 12B
# FULL WIDTH WHEN SIDEBAR HIDDEN + UI SCALE UP ONE LEVEL
# Base colors remain unchanged
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$ViewPath   = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath    = Join-Path $ProjectRoot 'public\assets\css\ui-layout-scale-fix.css'

$Stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir  = Join-Path $ProjectRoot "writable\backups\stage12b_$Stamp"

function Step([string]$Message) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
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
    $destination = Join-Path $BackupDir $relative
    $destinationDir = Split-Path $destination -Parent

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item $Path $destination -Force
}

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan."
}

if (-not (Test-Path $ViewPath)) {
    Fail "View BrowserNote tidak ditemukan."
}

$stage12aCss = Join-Path $ProjectRoot 'public\assets\css\ui-polish-fix.css'

if (-not (Test-Path $stage12aCss)) {
    Fail "Stage 12A belum ditemukan."
}

Ok "Project ditemukan"
Ok "Stage 12A terverifikasi"

Step "2. BACKUP"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $ViewPath,
    $CssPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. ADD FINAL LAYOUT CSS TO VIEW"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

$cssTag = '<link rel="stylesheet" href="<?= base_url(''assets/css/ui-layout-scale-fix.css'') ?>">'

if (-not $viewText.Contains('assets/css/ui-layout-scale-fix.css')) {
    $headClose = '</head>'

    if (-not $viewText.Contains($headClose)) {
        Fail "Tag </head> tidak ditemukan."
    }

    $viewText = $viewText.Replace(
        $headClose,
        $cssTag + "`r`n" + $headClose
    )

    Write-Utf8NoBom -Path $ViewPath -Content $viewText
}

Ok "Final layout CSS dimuat setelah CSS sebelumnya"

Step "4. CREATE FULLWIDTH + SCALE CSS"

$css = @'
/* ============================================================
   BrowserNote Stage 12B
   Full-width collapse + one-level UI enlargement
   IMPORTANT: no base colors are changed here.
   ============================================================ */

/* ---------- BASE DESKTOP SCALE +1 ---------- */

.app-shell {
    grid-template-columns: 260px minmax(0, 1fr) !important;
    width: 100vw !important;
    max-width: 100vw !important;
    overflow: hidden !important;
}

.sidebar {
    width: 260px !important;
    min-width: 260px !important;
    padding: 11px !important;
}

.workspace {
    width: 100% !important;
    min-width: 0 !important;
    max-width: none !important;
}

/* ---------- TRUE FULL WIDTH WHEN SIDEBAR HIDDEN ---------- */

/*
   The previous layout visually hid the sidebar but still retained
   part of the grid column. Force the sidebar column to zero.
*/
.app-shell.sidebar-collapsed {
    grid-template-columns: 0 minmax(0, 1fr) !important;
}

.app-shell.sidebar-collapsed .sidebar {
    width: 0 !important;
    min-width: 0 !important;
    max-width: 0 !important;
    padding-left: 0 !important;
    padding-right: 0 !important;
    border-right-width: 0 !important;
    overflow: hidden !important;
    visibility: hidden !important;
    pointer-events: none !important;
}

.app-shell.sidebar-collapsed .workspace {
    width: 100vw !important;
    min-width: 0 !important;
    max-width: 100vw !important;
}

.app-shell.sidebar-collapsed .topbar,
.app-shell.sidebar-collapsed .editor-host,
.app-shell.sidebar-collapsed .statusbar {
    width: 100% !important;
    max-width: none !important;
}

/* ---------- TOPBAR SCALE +1 ---------- */

.topbar {
    min-height: 56px !important;
    padding: 8px 14px !important;
    gap: 8px !important;
}

.show-sidebar-button {
    width: 31px !important;
    height: 31px !important;
    font-size: 15px !important;
}

.note-title {
    font-size: 16px !important;
    font-weight: 600 !important;
}

.note-status-badge {
    font-size: 9.5px !important;
}

.folder-select-label {
    font-size: 10px !important;
}

.folder-select {
    height: 32px !important;
    max-width: 165px !important;
    font-size: 11px !important;
}

.note-action-button,
.save-button {
    height: 32px !important;
    font-size: 10.5px !important;
}

.save-state {
    font-size: 10.5px !important;
}

/* ---------- SIDEBAR SCALE +1 ---------- */

.brand-mark {
    width: 33px !important;
    height: 33px !important;
    font-size: 13.5px !important;
}

.brand {
    font-size: 14px !important;
}

.brand-subtitle {
    font-size: 10px !important;
}

.new-note-button {
    min-height: 38px !important;
    font-size: 12.5px !important;
}

.quick-note-launcher,
.search-box,
.shortcut-help-button,
.export-backup-button {
    min-height: 35px !important;
}

.quick-note-launcher,
.shortcut-help-button,
.export-backup-button {
    font-size: 11px !important;
}

.search-box input {
    font-size: 12px !important;
}

.section-heading {
    min-height: 27px !important;
    font-size: 9.5px !important;
}

.note-item {
    padding: 8px 9px !important;
}

.note-item-title {
    font-size: 12.5px !important;
}

.note-item-meta {
    font-size: 10px !important;
}

.folder-item,
.nav-item {
    min-height: 32px !important;
    font-size: 11.5px !important;
}

/* ---------- TINYMCE CHROME SCALE +1 ---------- */

.tox .tox-menubar {
    min-height: 33px !important;
    padding: 3px 9px !important;
}

.tox .tox-mbtn {
    height: 31px !important;
    padding-left: 8px !important;
    padding-right: 8px !important;
    font-size: 12px !important;
}

.tox .tox-tbtn {
    width: 31px !important;
    height: 31px !important;
}

.tox .tox-tbtn--select {
    min-width: 88px !important;
    max-width: 138px !important;
}

.tox .tox-tbtn__select-label {
    font-size: 11px !important;
}

/* ---------- EDITOR CONTENT SCALE +1 ---------- */

/*
   This only affects editor rendering.
   It does not rewrite stored note HTML.
*/
.tox-edit-area__iframe {
    width: 100% !important;
}

/* ---------- APP STATUS BAR ---------- */

.statusbar {
    min-height: 29px !important;
    padding-left: 12px !important;
    padding-right: 12px !important;
    font-size: 10px !important;
}

/* ---------- FULLSCREEN / NARROW WINDOW SAFETY ---------- */

@media (max-width: 1100px) {
    .app-shell {
        grid-template-columns: 245px minmax(0, 1fr) !important;
    }

    .sidebar {
        width: 245px !important;
        min-width: 245px !important;
    }

    .app-shell.sidebar-collapsed {
        grid-template-columns: 0 minmax(0, 1fr) !important;
    }

    .app-shell.sidebar-collapsed .sidebar {
        width: 0 !important;
        min-width: 0 !important;
    }
}

@media (max-width: 760px) {
    .app-shell {
        grid-template-columns: 225px minmax(0, 1fr) !important;
    }

    .sidebar {
        width: 225px !important;
        min-width: 225px !important;
    }

    .app-shell.sidebar-collapsed {
        grid-template-columns: 0 minmax(0, 1fr) !important;
    }

    .app-shell.sidebar-collapsed .sidebar {
        width: 0 !important;
        min-width: 0 !important;
    }
}
'@

Write-Utf8NoBom -Path $CssPath -Content $css

Ok "Full-width collapse CSS dibuat"
Ok "UI scale +1 diterapkan"
Ok "Warna dasar tidak diubah"

Step "5. STATIC VERIFICATION"

$viewVerify = [System.IO.File]::ReadAllText($ViewPath)
$cssVerify  = [System.IO.File]::ReadAllText($CssPath)

if (-not $viewVerify.Contains('assets/css/ui-layout-scale-fix.css')) {
    Fail "View belum memuat final CSS."
}

foreach ($fragment in @(
    '.app-shell.sidebar-collapsed',
    'grid-template-columns: 0 minmax(0, 1fr) !important',
    '.app-shell.sidebar-collapsed .workspace',
    'width: 100vw !important',
    'font-size: 16px !important',
    'width: 260px !important'
)) {
    if (-not $cssVerify.Contains($fragment)) {
        Fail "CSS marker hilang: $fragment"
    }
}

Ok "Static verification PASS"

Step "6. HTTP VERIFICATION"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8 `
        -ErrorAction Stop

    $cssHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/css/ui-layout-scale-fix.css" `
        -UseBasicParsing `
        -TimeoutSec 8 `
        -ErrorAction Stop
}
catch {
    Fail "Root atau final CSS tidak dapat diakses."
}

if ($page.StatusCode -ne 200) {
    Fail "BrowserNote root bukan HTTP 200."
}

if ($cssHttp.StatusCode -ne 200) {
    Fail "Final CSS bukan HTTP 200."
}

if ($page.Content -notlike '*ui-layout-scale-fix.css*') {
    Fail "Root belum memuat final CSS."
}

Ok "HTTP verification PASS"

Step "STAGE 12B PASS"

Write-Host ""
Write-Host "Project          : $ProjectRoot" -ForegroundColor White
Write-Host "URL              : $BaseUrl/" -ForegroundColor White
Write-Host "Base colors      : UNCHANGED" -ForegroundColor White
Write-Host "Sidebar desktop  : 260 px" -ForegroundColor White
Write-Host "Sidebar hidden   : TRUE 100% WORKSPACE" -ForegroundColor White
Write-Host "Topbar           : scale +1" -ForegroundColor White
Write-Host "TinyMCE toolbar  : scale +1" -ForegroundColor White
Write-Host "Sidebar text     : scale +1" -ForegroundColor White
Write-Host "Main title       : 16 px" -ForegroundColor White
Write-Host ""
Write-Host "WAJIB UJI:" -ForegroundColor Green
Write-Host "1. Tutup tab BrowserNote." -ForegroundColor White
Write-Host "2. Buka lagi $BaseUrl/" -ForegroundColor White
Write-Host "3. Tekan Ctrl+F5." -ForegroundColor White
Write-Host "4. Hide sidebar." -ForegroundColor White
Write-Host "5. Pastikan editor benar-benar memenuhi lebar layar." -ForegroundColor White
Write-Host "6. Show sidebar kembali." -ForegroundColor White
Write-Host "7. Pastikan seluruh UI terasa satu tingkat lebih besar." -ForegroundColor White
