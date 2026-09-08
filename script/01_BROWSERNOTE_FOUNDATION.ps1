#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 01 FOUNDATION
# Target  : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectName = 'browsernote'
$Htdocs      = 'C:\xampp\htdocs'
$ProjectRoot = Join-Path $Htdocs $ProjectName
$BaseUrl     = 'http://localhost/browsernote/public/'
$DbFile      = Join-Path $ProjectRoot 'writable\browsernote.sqlite'

function Step([string]$Message) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
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

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Resolve-PHP {
    $cmd = Get-Command php -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $xamppPhp = 'C:\xampp\php\php.exe'
    if (Test-Path $xamppPhp) { return $xamppPhp }

    return $null
}

function Resolve-Composer {
    $cmd = Get-Command composer -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        'C:\ProgramData\ComposerSetup\bin\composer.bat',
        'C:\ProgramData\ComposerSetup\bin\composer.phar',
        'C:\xampp\php\composer.phar'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

function Invoke-Composer {
    param(
        [Parameter(Mandatory=$true)][string]$ComposerPath,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    if ($ComposerPath.ToLower().EndsWith('.phar')) {
        & $script:PhpExe $ComposerPath @Arguments
    } else {
        & $ComposerPath @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Composer gagal dengan exit code $LASTEXITCODE."
    }
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Value
    )

    $content = Get-Content $Path -Raw
    $escapedKey = [regex]::Escape($Key)
    $pattern = "(?m)^\s*#?\s*$escapedKey\s*=.*$"
    $newLine = "$Key = $Value"

    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $newLine, 1)
    } else {
        $content = $content.TrimEnd() + "`r`n$newLine`r`n"
    }

    Write-Utf8NoBom -Path $Path -Content $content
}

Step "1. PRECHECK"

if (-not (Test-Path $Htdocs)) {
    Fail "Folder htdocs tidak ditemukan: $Htdocs"
}
Ok "htdocs ditemukan: $Htdocs"

$script:PhpExe = Resolve-PHP
if (-not $script:PhpExe) {
    Fail "PHP tidak ditemukan. Pastikan XAMPP terpasang."
}
Ok "PHP ditemukan: $script:PhpExe"

$phpVersion = & $script:PhpExe -r "echo PHP_VERSION;"
Ok "PHP version: $phpVersion"

$modules = & $script:PhpExe -m
if ($modules -notcontains 'sqlite3') {
    Fail "Ekstensi sqlite3 belum aktif pada PHP XAMPP. Aktifkan extension=sqlite3 di php.ini lalu jalankan ulang script."
}
Ok "PHP sqlite3 aktif"

$ComposerExe = Resolve-Composer
if (-not $ComposerExe) {
    Fail "Composer tidak ditemukan. Instal Composer terlebih dahulu atau pastikan composer ada di PATH."
}
Ok "Composer ditemukan: $ComposerExe"

Step "2. CREATE / VERIFY CODEIGNITER PROJECT"

if (Test-Path $ProjectRoot) {
    if (Test-Path (Join-Path $ProjectRoot 'spark')) {
        Warn "Project sudah ada. Instalasi CodeIgniter dilewati."
    } else {
        $items = Get-ChildItem $ProjectRoot -Force -ErrorAction SilentlyContinue
        if ($items.Count -gt 0) {
            Fail "Folder $ProjectRoot sudah ada tetapi bukan project CodeIgniter yang valid."
        }
    }
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Push-Location $Htdocs
    try {
        Invoke-Composer -ComposerPath $ComposerExe -Arguments @(
            'create-project',
            'codeigniter4/appstarter',
            $ProjectName,
            '--no-interaction'
        )
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "Project CodeIgniter gagal dibuat."
}
Ok "CodeIgniter project siap"

Step "3. CONFIGURE ENVIRONMENT"

$EnvFile = Join-Path $ProjectRoot '.env'
$EnvTemplate = Join-Path $ProjectRoot 'env'

if (-not (Test-Path $EnvFile)) {
    if (-not (Test-Path $EnvTemplate)) {
        Fail "Template env tidak ditemukan."
    }
    Copy-Item $EnvTemplate $EnvFile
    Ok ".env dibuat"
} else {
    Warn ".env sudah ada, nilai BrowserNote akan diperbarui."
}

$dbForward = $DbFile.Replace('\','/')

Set-EnvValue -Path $EnvFile -Key 'CI_ENVIRONMENT' -Value 'development'
Set-EnvValue -Path $EnvFile -Key 'app.baseURL' -Value "'$BaseUrl'"
Set-EnvValue -Path $EnvFile -Key 'app.indexPage' -Value "''"
Set-EnvValue -Path $EnvFile -Key 'database.default.DBDriver' -Value 'SQLite3'
Set-EnvValue -Path $EnvFile -Key 'database.default.database' -Value "'$dbForward'"

Ok "Base URL: $BaseUrl"
Ok "SQLite database path dikonfigurasi"

Step "4. PREPARE SQLITE FILE"

$WritableDir = Join-Path $ProjectRoot 'writable'
if (-not (Test-Path $WritableDir)) {
    New-Item -ItemType Directory -Path $WritableDir -Force | Out-Null
}

if (-not (Test-Path $DbFile)) {
    New-Item -ItemType File -Path $DbFile -Force | Out-Null
    Ok "SQLite file dibuat: $DbFile"
} else {
    Warn "SQLite file sudah ada."
}

Step "5. CREATE BROWSERNOTE APP SHELL"

$ControllerPath = Join-Path $ProjectRoot 'app\Controllers\Notes.php'
$ViewDir        = Join-Path $ProjectRoot 'app\Views\notes'
$ViewPath       = Join-Path $ViewDir 'index.php'
$CssDir         = Join-Path $ProjectRoot 'public\assets\css'
$JsDir          = Join-Path $ProjectRoot 'public\assets\js'
$CssPath        = Join-Path $CssDir 'app.css'
$JsPath         = Join-Path $JsDir 'app.js'
$RoutesPath     = Join-Path $ProjectRoot 'app\Config\Routes.php'

New-Item -ItemType Directory -Path $ViewDir -Force | Out-Null
New-Item -ItemType Directory -Path $CssDir -Force | Out-Null
New-Item -ItemType Directory -Path $JsDir -Force | Out-Null

$controller = @'
<?php

namespace App\Controllers;

class Notes extends BaseController
{
    public function index()
    {
        helper('url');

        return view('notes/index');
    }
}
'@
Write-Utf8NoBom -Path $ControllerPath -Content $controller

$routes = @'
<?php

use CodeIgniter\Router\RouteCollection;

/**
 * @var RouteCollection $routes
 */
$routes->get('/', 'Notes::index');
'@
Write-Utf8NoBom -Path $RoutesPath -Content $routes

$view = @'
<!doctype html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>BrowserNote</title>
    <link rel="stylesheet" href="<?= base_url('assets/css/app.css') ?>">
</head>
<body>
<div class="app-shell" id="appShell">
    <aside class="sidebar" id="sidebar">
        <div class="brand-row">
            <div class="brand">BrowserNote</div>
            <button class="icon-button" id="collapseSidebar" type="button" title="Ciutkan sidebar">‹</button>
        </div>

        <button class="new-note-button" type="button">+ Catatan Baru</button>

        <label class="search-box">
            <span>⌕</span>
            <input type="search" placeholder="Cari catatan..." disabled>
        </label>

        <nav class="nav-block">
            <div class="nav-label">CATATAN</div>
            <button class="nav-item active" type="button">Catatan awal</button>
        </nav>

        <nav class="nav-block">
            <div class="nav-label">FOLDER</div>
            <button class="nav-item" type="button">Belum ada folder</button>
        </nav>

        <nav class="nav-block nav-bottom">
            <button class="nav-item" type="button">Arsip</button>
            <button class="nav-item" type="button">Sampah</button>
        </nav>
    </aside>

    <main class="workspace">
        <header class="topbar">
            <button class="show-sidebar-button" id="showSidebar" type="button" title="Tampilkan sidebar">☰</button>
            <input class="note-title" value="Catatan awal" aria-label="Judul catatan" disabled>
            <div class="top-actions">
                <span class="stage-badge">Stage 01</span>
            </div>
        </header>

        <section class="editor-toolbar-placeholder">
            Editor rich text akan dipasang pada Stage 04
        </section>

        <section class="editor-area">
            <div class="editor-placeholder">
                <h1>BrowserNote siap.</h1>
                <p>Shell full-browser berhasil dibuat.</p>
                <p>Stage berikutnya akan menambahkan database, API, TinyMCE, autosave, folder, arsip, sampah, dan pencarian.</p>
            </div>
        </section>

        <footer class="statusbar">
            <span>Foundation aktif</span>
            <span>SQLite siap</span>
        </footer>
    </main>
</div>

<script src="<?= base_url('assets/js/app.js') ?>"></script>
</body>
</html>
'@
Write-Utf8NoBom -Path $ViewPath -Content $view

$css = @'
:root {
    --sidebar-width: 248px;
    --border: #e5e7eb;
    --muted: #6b7280;
    --text: #111827;
    --surface: #ffffff;
    --surface-soft: #f8fafc;
    --hover: #f1f5f9;
    --accent: #111827;
}

* {
    box-sizing: border-box;
}

html,
body {
    width: 100%;
    height: 100%;
    margin: 0;
}

body {
    overflow: hidden;
    font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    color: var(--text);
    background: var(--surface);
}

button,
input {
    font: inherit;
}

button {
    cursor: pointer;
}

.app-shell {
    width: 100vw;
    height: 100vh;
    display: grid;
    grid-template-columns: var(--sidebar-width) minmax(0, 1fr);
    background: var(--surface);
}

.app-shell.sidebar-collapsed {
    grid-template-columns: 0 minmax(0, 1fr);
}

.sidebar {
    min-width: 0;
    height: 100vh;
    border-right: 1px solid var(--border);
    background: var(--surface-soft);
    padding: 12px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    overflow: hidden;
    transition: transform 140ms ease;
}

.sidebar-collapsed .sidebar {
    transform: translateX(-100%);
    pointer-events: none;
}

.brand-row {
    height: 38px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
}

.brand {
    font-size: 16px;
    font-weight: 750;
    letter-spacing: -0.02em;
}

.icon-button,
.show-sidebar-button {
    width: 32px;
    height: 32px;
    border: 1px solid var(--border);
    border-radius: 7px;
    background: var(--surface);
    color: var(--text);
}

.new-note-button {
    width: 100%;
    min-height: 38px;
    border: 1px solid #d1d5db;
    border-radius: 7px;
    background: var(--accent);
    color: white;
    font-weight: 650;
}

.search-box {
    height: 38px;
    display: flex;
    align-items: center;
    gap: 8px;
    border: 1px solid var(--border);
    border-radius: 7px;
    background: var(--surface);
    padding: 0 10px;
}

.search-box input {
    min-width: 0;
    width: 100%;
    border: 0;
    outline: 0;
    background: transparent;
}

.nav-block {
    display: flex;
    flex-direction: column;
    gap: 3px;
}

.nav-label {
    padding: 6px 8px 4px;
    font-size: 10px;
    font-weight: 750;
    letter-spacing: 0.08em;
    color: var(--muted);
}

.nav-item {
    width: 100%;
    min-height: 34px;
    padding: 7px 9px;
    border: 0;
    border-radius: 6px;
    text-align: left;
    color: var(--text);
    background: transparent;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.nav-item:hover,
.nav-item.active {
    background: var(--hover);
}

.nav-item.active {
    font-weight: 650;
}

.nav-bottom {
    margin-top: auto;
}

.workspace {
    min-width: 0;
    height: 100vh;
    display: grid;
    grid-template-rows: 52px 40px minmax(0, 1fr) 30px;
    background: var(--surface);
}

.topbar {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border-bottom: 1px solid var(--border);
}

.show-sidebar-button {
    display: none;
}

.sidebar-collapsed .show-sidebar-button {
    display: inline-grid;
    place-items: center;
}

.note-title {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: transparent;
    color: var(--text);
    font-size: 17px;
    font-weight: 700;
}

.top-actions {
    display: flex;
    align-items: center;
    gap: 8px;
}

.stage-badge {
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 5px 9px;
    color: var(--muted);
    font-size: 12px;
}

.editor-toolbar-placeholder {
    display: flex;
    align-items: center;
    padding: 0 16px;
    border-bottom: 1px solid var(--border);
    color: var(--muted);
    font-size: 12px;
}

.editor-area {
    min-height: 0;
    overflow: auto;
    padding: 26px clamp(20px, 4vw, 64px);
    background: var(--surface);
}

.editor-placeholder {
    max-width: 920px;
}

.editor-placeholder h1 {
    margin: 0 0 12px;
    font-size: 28px;
    letter-spacing: -0.03em;
}

.editor-placeholder p {
    max-width: 760px;
    line-height: 1.65;
    color: #374151;
}

.statusbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 0 14px;
    border-top: 1px solid var(--border);
    color: var(--muted);
    font-size: 11px;
}

@media (max-width: 800px) {
    :root {
        --sidebar-width: 220px;
    }

    .editor-area {
        padding: 20px;
    }
}
'@
Write-Utf8NoBom -Path $CssPath -Content $css

$js = @'
(() => {
    const appShell = document.getElementById('appShell');
    const collapse = document.getElementById('collapseSidebar');
    const show = document.getElementById('showSidebar');

    collapse?.addEventListener('click', () => {
        appShell.classList.add('sidebar-collapsed');
        localStorage.setItem('browsernote.sidebar', 'collapsed');
    });

    show?.addEventListener('click', () => {
        appShell.classList.remove('sidebar-collapsed');
        localStorage.setItem('browsernote.sidebar', 'open');
    });

    if (localStorage.getItem('browsernote.sidebar') === 'collapsed') {
        appShell.classList.add('sidebar-collapsed');
    }
})();
'@
Write-Utf8NoBom -Path $JsPath -Content $js

Ok "Controller Notes dibuat"
Ok "Route root dibuat"
Ok "View full-browser dibuat"
Ok "CSS foundation dibuat"
Ok "JavaScript sidebar dibuat"

Step "6. CODEIGNITER VERIFICATION"

Push-Location $ProjectRoot
try {
    & $script:PhpExe spark routes
    if ($LASTEXITCODE -ne 0) {
        Fail "php spark routes gagal."
    }
} finally {
    Pop-Location
}

Ok "Route verification PASS"

Step "7. OPTIONAL HTTP CHECK"

try {
    $response = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 3
    if ($response.StatusCode -eq 200) {
        Ok "HTTP 200: $BaseUrl"
    } else {
        Warn "URL merespons dengan status $($response.StatusCode)"
    }
}
catch {
    Warn "Apache kemungkinan belum aktif. Start Apache di XAMPP lalu buka $BaseUrl"
}

Step "STAGE 01 PASS"

Write-Host ""
Write-Host "Project : $ProjectRoot" -ForegroundColor White
Write-Host "URL     : $BaseUrl" -ForegroundColor White
Write-Host "Database: $DbFile" -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya: Stage 02 - Database + Models" -ForegroundColor Green
