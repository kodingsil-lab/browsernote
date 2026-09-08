#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 04
# TINYMCE SELF-HOSTED + FULL RICH EDITOR
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'
$ViewPath    = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath     = Join-Path $ProjectRoot 'public\assets\css\app.css'
$JsPath      = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$OldJsPath   = Join-Path $ProjectRoot 'public\assets\js\app.js'
$TinyVendor  = Join-Path $ProjectRoot 'vendor\tinymce\tinymce'
$TinyPublic  = Join-Path $ProjectRoot 'public\assets\vendor\tinymce'
$ComposerJson = Join-Path $ProjectRoot 'composer.json'
$ComposerLock = Join-Path $ProjectRoot 'composer.lock'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage04_$Stamp"

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
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

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
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "spark tidak ditemukan."
}

if (-not (Test-Path $ViewPath)) {
    Fail "View BrowserNote tidak ditemukan: $ViewPath"
}

if (-not (Test-Path $ComposerJson)) {
    Fail "composer.json tidak ditemukan."
}

$script:PhpExe = Resolve-PHP
if (-not $script:PhpExe) {
    Fail "PHP tidak ditemukan."
}

$ComposerExe = Resolve-Composer
if (-not $ComposerExe) {
    Fail "Composer tidak ditemukan."
}

Ok "Project ditemukan"
Ok "PHP ditemukan: $script:PhpExe"
Ok "Composer ditemukan: $ComposerExe"
Ok "View BrowserNote ditemukan"

Step "2. BACKUP CURRENT FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $ViewPath,
    $CssPath,
    $JsPath,
    $OldJsPath,
    $ComposerJson,
    $ComposerLock
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. INSTALL TINYMCE 8 WITH COMPOSER"

Push-Location $ProjectRoot
try {
    Invoke-Composer -ComposerPath $ComposerExe -Arguments @(
        'require',
        'tinymce/tinymce:8.9.0',
        '--no-interaction',
        '--no-progress'
    )
}
catch {
    Fail $_.Exception.Message
}
finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $TinyVendor 'tinymce.min.js'))) {
    Fail "TinyMCE package tidak ditemukan setelah Composer install: $TinyVendor"
}

Ok "TinyMCE Composer package terpasang"

Step "4. COPY TINYMCE TO PUBLIC ASSETS"

if (Test-Path $TinyPublic) {
    Remove-Item $TinyPublic -Recurse -Force
}

$TinyPublicParent = Split-Path $TinyPublic -Parent
New-Item -ItemType Directory -Path $TinyPublicParent -Force | Out-Null

Copy-Item $TinyVendor $TinyPublic -Recurse -Force

$requiredTinyFiles = @(
    (Join-Path $TinyPublic 'tinymce.min.js'),
    (Join-Path $TinyPublic 'plugins\table\plugin.min.js'),
    (Join-Path $TinyPublic 'plugins\codesample\plugin.min.js'),
    (Join-Path $TinyPublic 'plugins\code\plugin.min.js'),
    (Join-Path $TinyPublic 'plugins\fullscreen\plugin.min.js'),
    (Join-Path $TinyPublic 'skins\ui\oxide\skin.min.css')
)

foreach ($file in $requiredTinyFiles) {
    if (-not (Test-Path $file)) {
        Fail "Aset TinyMCE wajib tidak ditemukan: $file"
    }
}

Ok "TinyMCE self-hosted disalin ke public/assets/vendor/tinymce"

Step "5. CREATE FULL-BROWSER VIEW"

$view = @'
<!doctype html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <title>BrowserNote</title>

    <link rel="stylesheet" href="<?= base_url('assets/css/app.css') ?>">
</head>
<body>
<div class="app-shell" id="appShell">
    <aside class="sidebar" id="sidebar">
        <div class="brand-row">
            <div class="brand-wrap">
                <div class="brand-mark">N</div>
                <div>
                    <div class="brand">BrowserNote</div>
                    <div class="brand-subtitle">local notes</div>
                </div>
            </div>

            <button
                class="icon-button"
                id="collapseSidebar"
                type="button"
                aria-label="Ciutkan sidebar"
                title="Ciutkan sidebar"
            >‹</button>
        </div>

        <button class="new-note-button" id="newNoteButton" type="button">
            <span>＋</span>
            <span>Catatan Baru</span>
        </button>

        <label class="search-box is-disabled" title="Pencarian akan diaktifkan pada Stage 09">
            <span class="search-icon">⌕</span>
            <input
                type="search"
                placeholder="Cari catatan..."
                aria-label="Cari catatan"
                disabled
            >
        </label>

        <section class="sidebar-section notes-section">
            <div class="section-heading">
                <span>CATATAN</span>
                <span class="section-count" id="noteCount">0</span>
            </div>

            <div class="note-list" id="noteList">
                <div class="sidebar-empty">Memuat catatan...</div>
            </div>
        </section>

        <section class="sidebar-section folder-preview">
            <div class="section-heading">
                <span>FOLDER</span>
            </div>

            <div class="nav-item muted">
                <span class="nav-icon">□</span>
                <span>Folder aktif di Stage 07</span>
            </div>
        </section>

        <div class="sidebar-footer">
            <button class="nav-item muted" type="button" disabled>
                <span class="nav-icon">◇</span>
                <span>Arsip</span>
            </button>

            <button class="nav-item muted" type="button" disabled>
                <span class="nav-icon">×</span>
                <span>Sampah</span>
            </button>
        </div>
    </aside>

    <main class="workspace">
        <header class="topbar">
            <button
                class="show-sidebar-button"
                id="showSidebar"
                type="button"
                aria-label="Tampilkan sidebar"
                title="Tampilkan sidebar"
            >☰</button>

            <input
                class="note-title"
                id="noteTitle"
                value=""
                placeholder="Catatan tanpa judul"
                maxlength="255"
                autocomplete="off"
                aria-label="Judul catatan"
            >

            <div class="save-state" id="saveState" data-state="ready">
                Siap
            </div>

            <button class="save-button" id="saveButton" type="button">
                Simpan
            </button>
        </header>

        <section class="editor-host" id="editorHost">
            <textarea id="noteEditor" aria-label="Isi catatan"></textarea>
        </section>

        <footer class="statusbar">
            <div class="status-left">
                <span id="currentNoteInfo">Belum ada catatan aktif</span>
            </div>

            <div class="status-right">
                <span id="wordCount">0 kata</span>
                <span class="status-separator">•</span>
                <span id="charCount">0 karakter</span>
                <span class="status-separator">•</span>
                <span>TinyMCE lokal</span>
            </div>
        </footer>
    </main>
</div>

<div class="toast" id="toast" role="status" aria-live="polite"></div>

<script>
window.BrowserNoteConfig = {
    baseUrl: <?= json_encode(rtrim(base_url(), '/'), JSON_UNESCAPED_SLASHES) ?>,
    tinyMceBase: <?= json_encode(rtrim(base_url('assets/vendor/tinymce'), '/'), JSON_UNESCAPED_SLASHES) ?>
};
</script>

<script src="<?= base_url('assets/vendor/tinymce/tinymce.min.js') ?>"></script>
<script src="<?= base_url('assets/js/browsernote.js') ?>"></script>
</body>
</html>
'@

Write-Utf8NoBom -Path $ViewPath -Content $view
Ok "View full-browser dibuat"

Step "6. CREATE FULL-BROWSER CSS"

$css = @'
:root {
    --sidebar-width: 252px;
    --topbar-height: 50px;
    --statusbar-height: 28px;

    --bg: #ffffff;
    --surface: #ffffff;
    --sidebar: #f7f8fa;
    --surface-soft: #f2f4f7;
    --surface-hover: #e9edf2;

    --border: #dfe3e8;
    --border-strong: #ccd2d9;

    --text: #17191c;
    --text-soft: #59616b;
    --text-muted: #8a929d;

    --accent: #20242a;
    --accent-hover: #0f1114;

    --success: #277645;
    --warning: #9b6500;
    --danger: #b42318;

    --radius: 7px;
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
    background: var(--bg);
    color: var(--text);
    font-family:
        Inter,
        ui-sans-serif,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        Roboto,
        Helvetica,
        Arial,
        sans-serif;
    font-size: 14px;
}

button,
input,
textarea {
    font: inherit;
}

button {
    color: inherit;
}

.app-shell {
    width: 100vw;
    height: 100vh;
    display: grid;
    grid-template-columns: var(--sidebar-width) minmax(0, 1fr);
    overflow: hidden;
    background: var(--surface);
}

.app-shell.sidebar-collapsed {
    grid-template-columns: 0 minmax(0, 1fr);
}

.sidebar {
    min-width: 0;
    width: var(--sidebar-width);
    height: 100vh;
    padding: 10px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    overflow: hidden;
    border-right: 1px solid var(--border);
    background: var(--sidebar);
    transition: transform 140ms ease;
}

.sidebar-collapsed .sidebar {
    transform: translateX(-100%);
    pointer-events: none;
}

.brand-row {
    height: 42px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
}

.brand-wrap {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 9px;
}

.brand-mark {
    width: 30px;
    height: 30px;
    flex: 0 0 30px;
    display: grid;
    place-items: center;
    border-radius: 8px;
    background: var(--accent);
    color: #ffffff;
    font-weight: 800;
    font-size: 13px;
}

.brand {
    font-weight: 760;
    letter-spacing: -0.02em;
    line-height: 1.1;
}

.brand-subtitle {
    margin-top: 2px;
    color: var(--text-muted);
    font-size: 10px;
    letter-spacing: 0.02em;
}

.icon-button,
.show-sidebar-button {
    width: 32px;
    height: 32px;
    flex: 0 0 32px;
    display: inline-grid;
    place-items: center;
    padding: 0;
    border: 1px solid transparent;
    border-radius: var(--radius);
    background: transparent;
    cursor: pointer;
}

.icon-button:hover,
.show-sidebar-button:hover {
    border-color: var(--border);
    background: var(--surface);
}

.new-note-button {
    width: 100%;
    height: 38px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    border: 1px solid var(--accent);
    border-radius: var(--radius);
    background: var(--accent);
    color: #ffffff;
    font-weight: 680;
    cursor: pointer;
}

.new-note-button:hover {
    background: var(--accent-hover);
}

.new-note-button:disabled {
    opacity: 0.55;
    cursor: wait;
}

.search-box {
    height: 36px;
    display: flex;
    align-items: center;
    gap: 7px;
    padding: 0 9px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--surface);
}

.search-box.is-disabled {
    opacity: 0.68;
}

.search-icon {
    color: var(--text-muted);
    font-size: 17px;
}

.search-box input {
    width: 100%;
    min-width: 0;
    border: 0;
    outline: 0;
    background: transparent;
    color: var(--text);
}

.search-box input::placeholder {
    color: var(--text-muted);
}

.sidebar-section {
    min-height: 0;
}

.notes-section {
    flex: 1 1 auto;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.section-heading {
    min-height: 27px;
    padding: 6px 7px 4px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: var(--text-muted);
    font-size: 10px;
    font-weight: 760;
    letter-spacing: 0.08em;
}

.section-count {
    min-width: 20px;
    text-align: right;
    letter-spacing: 0;
}

.note-list {
    min-height: 0;
    overflow-y: auto;
    scrollbar-width: thin;
}

.note-item {
    width: 100%;
    min-height: 48px;
    display: block;
    padding: 7px 9px;
    border: 1px solid transparent;
    border-radius: var(--radius);
    background: transparent;
    text-align: left;
    cursor: pointer;
}

.note-item:hover {
    background: var(--surface-hover);
}

.note-item.active {
    border-color: var(--border);
    background: var(--surface);
}

.note-item-title {
    overflow: hidden;
    color: var(--text);
    font-size: 13px;
    font-weight: 610;
    line-height: 1.3;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.note-item-meta {
    margin-top: 4px;
    overflow: hidden;
    color: var(--text-muted);
    font-size: 10px;
    line-height: 1.2;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.sidebar-empty {
    padding: 14px 9px;
    color: var(--text-muted);
    font-size: 12px;
    line-height: 1.5;
}

.folder-preview {
    flex: 0 0 auto;
    padding-top: 2px;
    border-top: 1px solid var(--border);
}

.nav-item {
    width: 100%;
    min-height: 34px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    border: 0;
    border-radius: var(--radius);
    background: transparent;
    text-align: left;
}

.nav-item.muted {
    color: var(--text-muted);
}

.nav-icon {
    width: 16px;
    flex: 0 0 16px;
    text-align: center;
}

.sidebar-footer {
    flex: 0 0 auto;
    padding-top: 5px;
    border-top: 1px solid var(--border);
}

.workspace {
    min-width: 0;
    height: 100vh;
    display: grid;
    grid-template-rows:
        var(--topbar-height)
        minmax(0, 1fr)
        var(--statusbar-height);
    overflow: hidden;
    background: var(--surface);
}

.topbar {
    min-width: 0;
    height: var(--topbar-height);
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px;
    border-bottom: 1px solid var(--border);
    background: var(--surface);
}

.show-sidebar-button {
    display: none;
}

.sidebar-collapsed .show-sidebar-button {
    display: inline-grid;
}

.note-title {
    flex: 1 1 auto;
    min-width: 80px;
    height: 36px;
    padding: 0 4px;
    border: 1px solid transparent;
    border-radius: 5px;
    outline: none;
    background: transparent;
    color: var(--text);
    font-size: 16px;
    font-weight: 690;
    letter-spacing: -0.015em;
}

.note-title:hover,
.note-title:focus {
    border-color: var(--border);
    background: var(--surface-soft);
}

.save-state {
    flex: 0 0 auto;
    color: var(--text-muted);
    font-size: 11px;
    white-space: nowrap;
}

.save-state[data-state="dirty"] {
    color: var(--warning);
}

.save-state[data-state="saving"] {
    color: var(--text-soft);
}

.save-state[data-state="saved"] {
    color: var(--success);
}

.save-state[data-state="error"] {
    color: var(--danger);
}

.save-button {
    height: 32px;
    flex: 0 0 auto;
    padding: 0 13px;
    border: 1px solid var(--border-strong);
    border-radius: var(--radius);
    background: var(--surface);
    color: var(--text);
    font-weight: 640;
    cursor: pointer;
}

.save-button:hover:not(:disabled) {
    background: var(--surface-soft);
}

.save-button:disabled {
    opacity: 0.48;
    cursor: default;
}

.editor-host {
    position: relative;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
    background: var(--surface);
}

#noteEditor {
    visibility: hidden;
}

.editor-host > .tox-tinymce {
    width: 100% !important;
    max-width: none !important;
    border: 0 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
}

.editor-host .tox .tox-editor-header {
    border-bottom: 1px solid var(--border);
    box-shadow: none !important;
}

.editor-host .tox .tox-toolbar-overlord,
.editor-host .tox .tox-toolbar__primary,
.editor-host .tox .tox-menubar {
    background: #ffffff;
}

.editor-host .tox .tox-edit-area::before {
    border: 0 !important;
}

.statusbar {
    min-width: 0;
    height: var(--statusbar-height);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 0 11px;
    overflow: hidden;
    border-top: 1px solid var(--border);
    background: var(--surface-soft);
    color: var(--text-muted);
    font-size: 10px;
    white-space: nowrap;
}

.status-left,
.status-right {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 6px;
    overflow: hidden;
}

.status-left {
    text-overflow: ellipsis;
}

.status-right {
    flex: 0 0 auto;
}

.status-separator {
    color: #b1b7bf;
}

.toast {
    position: fixed;
    z-index: 999999;
    right: 14px;
    bottom: 40px;
    max-width: min(420px, calc(100vw - 28px));
    padding: 9px 12px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: #17191c;
    color: #ffffff;
    box-shadow: 0 8px 28px rgba(0, 0, 0, 0.16);
    font-size: 12px;
    opacity: 0;
    pointer-events: none;
    transform: translateY(5px);
    transition:
        opacity 120ms ease,
        transform 120ms ease;
}

.toast.show {
    opacity: 1;
    transform: translateY(0);
}

@media (max-width: 840px) {
    :root {
        --sidebar-width: 230px;
    }

    .save-state {
        display: none;
    }

    .status-right span:nth-child(n+4) {
        display: none;
    }
}
'@

Write-Utf8NoBom -Path $CssPath -Content $css
Ok "CSS full-browser dibuat"

Step "7. CREATE BROWSERNOTE EDITOR JAVASCRIPT"

$js = @'
(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiBase = `${config.baseUrl}/api/notes`;

    const state = {
        editor: null,
        notes: [],
        currentId: null,
        currentNote: null,
        dirty: false,
        saving: false,
        loading: false,
        toastTimer: null,
    };

    const el = {
        appShell: document.getElementById('appShell'),
        collapseSidebar: document.getElementById('collapseSidebar'),
        showSidebar: document.getElementById('showSidebar'),
        newNoteButton: document.getElementById('newNoteButton'),
        noteList: document.getElementById('noteList'),
        noteCount: document.getElementById('noteCount'),
        noteTitle: document.getElementById('noteTitle'),
        saveState: document.getElementById('saveState'),
        saveButton: document.getElementById('saveButton'),
        editorHost: document.getElementById('editorHost'),
        currentNoteInfo: document.getElementById('currentNoteInfo'),
        wordCount: document.getElementById('wordCount'),
        charCount: document.getElementById('charCount'),
        toast: document.getElementById('toast'),
    };

    function setSaveState(text, type = 'ready') {
        el.saveState.textContent = text;
        el.saveState.dataset.state = type;
    }

    function showToast(message) {
        el.toast.textContent = message;
        el.toast.classList.add('show');

        window.clearTimeout(state.toastTimer);
        state.toastTimer = window.setTimeout(() => {
            el.toast.classList.remove('show');
        }, 2200);
    }

    function escapeText(value) {
        return String(value ?? '');
    }

    function formatDate(value) {
        if (!value) {
            return '';
        }

        const normalized = value.includes('T')
            ? value
            : value.replace(' ', 'T');

        const date = new Date(normalized);

        if (Number.isNaN(date.getTime())) {
            return value;
        }

        return new Intl.DateTimeFormat('id-ID', {
            day: '2-digit',
            month: 'short',
            hour: '2-digit',
            minute: '2-digit',
        }).format(date);
    }

    async function request(url, options = {}) {
        const response = await fetch(url, {
            headers: {
                Accept: 'application/json',
                ...(options.body ? { 'Content-Type': 'application/json' } : {}),
                ...(options.headers || {}),
            },
            ...options,
        });

        let data = null;

        try {
            data = await response.json();
        } catch {
            throw new Error(`Respons server bukan JSON (${response.status}).`);
        }

        if (!response.ok || !data?.ok) {
            throw new Error(data?.message || `HTTP ${response.status}`);
        }

        return data;
    }

    function updateCounters() {
        if (!state.editor) {
            el.wordCount.textContent = '0 kata';
            el.charCount.textContent = '0 karakter';
            return;
        }

        const text = state.editor.getContent({ format: 'text' }) || '';
        const trimmed = text.trim();
        const words = trimmed === ''
            ? 0
            : trimmed.split(/\s+/u).filter(Boolean).length;

        el.wordCount.textContent = `${words.toLocaleString('id-ID')} kata`;
        el.charCount.textContent = `${text.length.toLocaleString('id-ID')} karakter`;
    }

    function markDirty() {
        if (state.loading || state.saving || !state.currentId) {
            return;
        }

        state.dirty = true;
        setSaveState('Belum disimpan', 'dirty');
        el.saveButton.disabled = false;
        updateCounters();
    }

    function setClean(savedText = 'Tersimpan') {
        state.dirty = false;
        setSaveState(savedText, 'saved');
        el.saveButton.disabled = true;

        if (state.editor) {
            state.editor.setDirty(false);
        }
    }

    function renderNotes() {
        el.noteList.innerHTML = '';
        el.noteCount.textContent = String(state.notes.length);

        if (state.notes.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'sidebar-empty';
            empty.textContent = 'Belum ada catatan aktif.';
            el.noteList.appendChild(empty);
            return;
        }

        for (const note of state.notes) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'note-item';

            if (Number(note.id) === Number(state.currentId)) {
                button.classList.add('active');
            }

            const title = document.createElement('div');
            title.className = 'note-item-title';
            title.textContent = escapeText(note.title || 'Catatan tanpa judul');

            const meta = document.createElement('div');
            meta.className = 'note-item-meta';

            const folder = note.folder_name
                ? `${note.folder_name} · `
                : '';

            meta.textContent = `${folder}${formatDate(note.updated_at)}`;

            button.append(title, meta);

            button.addEventListener('click', async () => {
                const id = Number(note.id);

                if (id === Number(state.currentId)) {
                    return;
                }

                try {
                    if (state.dirty) {
                        await saveCurrent({ quiet: true });
                    }

                    await openNote(id);
                } catch (error) {
                    handleError(error);
                }
            });

            el.noteList.appendChild(button);
        }
    }

    async function loadNotes(preferredId = null) {
        const response = await request(apiBase);
        state.notes = Array.isArray(response.data) ? response.data : [];
        renderNotes();

        if (state.notes.length === 0) {
            const created = await createNote({ open: false });
            await loadNotes(created.id);
            return;
        }

        const wanted = preferredId
            ? state.notes.find((item) => Number(item.id) === Number(preferredId))
            : null;

        const id = wanted
            ? Number(wanted.id)
            : Number(state.notes[0].id);

        await openNote(id);
    }

    async function openNote(id) {
        if (!state.editor) {
            return;
        }

        state.loading = true;
        setSaveState('Memuat...', 'saving');

        try {
            const response = await request(`${apiBase}/${id}`);
            const note = response.data;

            state.currentId = Number(note.id);
            state.currentNote = note;

            el.noteTitle.value = note.title || '';
            state.editor.setContent(note.content || '');
            state.editor.undoManager.clear();

            updateCounters();
            setClean('Tersimpan');

            el.currentNoteInfo.textContent = note.folder_name
                ? `#${note.id} · ${note.folder_name}`
                : `#${note.id} · Tanpa folder`;

            renderNotes();

            window.setTimeout(() => {
                state.editor.focus();
            }, 0);
        } finally {
            state.loading = false;
        }
    }

    async function createNote({ open = true } = {}) {
        if (state.dirty) {
            await saveCurrent({ quiet: true });
        }

        el.newNoteButton.disabled = true;
        setSaveState('Membuat...', 'saving');

        try {
            const response = await request(apiBase, {
                method: 'POST',
                body: JSON.stringify({
                    title: 'Catatan tanpa judul',
                    content: '<p></p>',
                }),
            });

            const created = response.data;

            if (open) {
                const list = await request(apiBase);
                state.notes = Array.isArray(list.data) ? list.data : [];
                renderNotes();
                await openNote(Number(created.id));
            }

            showToast('Catatan baru dibuat');
            return created;
        } finally {
            el.newNoteButton.disabled = false;
        }
    }

    async function saveCurrent({ quiet = false } = {}) {
        if (!state.currentId || !state.editor || state.saving) {
            return;
        }

        if (!state.dirty && quiet) {
            return;
        }

        state.saving = true;
        el.saveButton.disabled = true;
        setSaveState('Menyimpan...', 'saving');

        const title = el.noteTitle.value.trim() || 'Catatan tanpa judul';
        const content = state.editor.getContent();

        try {
            const response = await request(`${apiBase}/${state.currentId}`, {
                method: 'PATCH',
                body: JSON.stringify({
                    title,
                    content,
                }),
            });

            state.currentNote = response.data;
            el.noteTitle.value = response.data.title || title;

            const existing = state.notes.find(
                (item) => Number(item.id) === Number(state.currentId)
            );

            if (existing) {
                Object.assign(existing, response.data);
            }

            renderNotes();
            updateCounters();
            setClean('Tersimpan');

            if (!quiet) {
                showToast('Catatan tersimpan');
            }
        } catch (error) {
            state.dirty = true;
            el.saveButton.disabled = false;
            setSaveState('Gagal menyimpan', 'error');
            throw error;
        } finally {
            state.saving = false;
        }
    }

    function handleError(error) {
        console.error(error);
        setSaveState('Terjadi kesalahan', 'error');
        showToast(error?.message || 'Terjadi kesalahan.');
    }

    function editorPixelHeight() {
        return Math.max(420, Math.floor(el.editorHost.clientHeight));
    }

    function fitEditorToHost() {
        if (!state.editor) {
            return;
        }

        const container = state.editor.getContainer();

        if (container) {
            container.style.height = `${editorPixelHeight()}px`;
        }
    }

    async function initTinyMCE() {
        if (typeof window.tinymce === 'undefined') {
            throw new Error('TinyMCE lokal gagal dimuat.');
        }

        const editors = await window.tinymce.init({
            selector: '#noteEditor',

            base_url: config.tinyMceBase,
            suffix: '.min',
            license_key: 'gpl',

            height: editorPixelHeight(),
            resize: false,

            menubar: 'edit view insert format tools table help',

            plugins: [
                'advlist',
                'autolink',
                'lists',
                'link',
                'charmap',
                'preview',
                'anchor',
                'searchreplace',
                'visualblocks',
                'code',
                'fullscreen',
                'insertdatetime',
                'table',
                'codesample',
                'wordcount',
            ].join(' '),

            toolbar: [
                'undo redo | blocks fontfamily fontsize',
                'bold italic underline strikethrough | forecolor backcolor',
                'alignleft aligncenter alignright alignjustify',
                'bullist numlist outdent indent | blockquote',
                'link codesample table',
                'removeformat | searchreplace visualblocks code fullscreen | help',
            ].join(' | '),

            toolbar_mode: 'wrap',
            toolbar_sticky: false,

            table_toolbar: [
                'tableprops tabledelete',
                'tablerowprops tablecellprops',
                'tableinsertrowbefore tableinsertrowafter tabledeleterow',
                'tableinsertcolbefore tableinsertcolafter tabledeletecol',
                'tablemergecells tablesplitcells',
                'tablerowheader tablecolheader',
            ].join(' | '),

            table_appearance_options: true,
            table_advtab: true,
            table_cell_advtab: true,
            table_row_advtab: true,

            link_context_toolbar: true,
            browser_spellcheck: true,
            contextmenu: 'link table',

            codesample_languages: [
                { text: 'HTML/XML', value: 'markup' },
                { text: 'JavaScript', value: 'javascript' },
                { text: 'CSS', value: 'css' },
                { text: 'PHP', value: 'php' },
                { text: 'Python', value: 'python' },
                { text: 'Java', value: 'java' },
                { text: 'C', value: 'c' },
                { text: 'C#', value: 'csharp' },
                { text: 'C++', value: 'cpp' },
            ],

            content_style: `
                body {
                    margin: 0;
                    padding: 24px 28px 80px;
                    font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
                    font-size: 15px;
                    line-height: 1.62;
                    color: #17191c;
                    background: #ffffff;
                }

                p {
                    margin-top: 0;
                    margin-bottom: 0.8em;
                }

                h1, h2, h3, h4, h5, h6 {
                    line-height: 1.25;
                    margin-top: 1.25em;
                    margin-bottom: 0.55em;
                }

                h1:first-child,
                h2:first-child,
                h3:first-child {
                    margin-top: 0;
                }

                code:not(pre code) {
                    padding: 0.14em 0.34em;
                    border: 1px solid #e0e4e8;
                    border-radius: 4px;
                    background: #f5f6f8;
                    font-family: Consolas, "Cascadia Code", "Courier New", monospace;
                    font-size: 0.92em;
                }

                pre {
                    overflow-x: auto;
                    padding: 14px 16px;
                    border: 1px solid #dde2e7;
                    border-radius: 7px;
                    background: #f6f7f9;
                    font-family: Consolas, "Cascadia Code", "Courier New", monospace;
                    font-size: 13px;
                    line-height: 1.55;
                    white-space: pre;
                }

                blockquote {
                    margin: 1em 0;
                    padding: 0.4em 0 0.4em 14px;
                    border-left: 3px solid #c8ced6;
                    color: #505862;
                }

                table {
                    width: 100%;
                    margin: 1em 0;
                    border-collapse: collapse;
                }

                th,
                td {
                    min-width: 40px;
                    padding: 7px 9px;
                    border: 1px solid #cfd5dc;
                    vertical-align: top;
                }

                th {
                    background: #f1f3f5;
                    font-weight: 700;
                }

                a {
                    color: #2457a6;
                }
            `,

            setup(editor) {
                editor.on('init', () => {
                    state.editor = editor;
                    fitEditorToHost();
                    updateCounters();
                });

                editor.on('input change undo redo', () => {
                    markDirty();
                });

                editor.on('SetContent', () => {
                    updateCounters();
                });

                editor.on('keydown', (event) => {
                    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
                        event.preventDefault();
                        saveCurrent().catch(handleError);
                    }

                    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'n') {
                        event.preventDefault();
                        createNote().catch(handleError);
                    }
                });
            },
        });

        state.editor = editors[0] || window.tinymce.get('noteEditor');

        if (!state.editor) {
            throw new Error('Instance TinyMCE tidak terbentuk.');
        }

        fitEditorToHost();
    }

    function bindUI() {
        el.collapseSidebar.addEventListener('click', () => {
            el.appShell.classList.add('sidebar-collapsed');
            localStorage.setItem('browsernote.sidebar', 'collapsed');

            window.setTimeout(fitEditorToHost, 160);
        });

        el.showSidebar.addEventListener('click', () => {
            el.appShell.classList.remove('sidebar-collapsed');
            localStorage.setItem('browsernote.sidebar', 'open');

            window.setTimeout(fitEditorToHost, 160);
        });

        if (localStorage.getItem('browsernote.sidebar') === 'collapsed') {
            el.appShell.classList.add('sidebar-collapsed');
        }

        el.newNoteButton.addEventListener('click', () => {
            createNote().catch(handleError);
        });

        el.saveButton.addEventListener('click', () => {
            saveCurrent().catch(handleError);
        });

        el.noteTitle.addEventListener('input', () => {
            markDirty();
        });

        el.noteTitle.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                state.editor?.focus();
            }

            if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
                event.preventDefault();
                saveCurrent().catch(handleError);
            }
        });

        document.addEventListener('keydown', (event) => {
            const key = event.key.toLowerCase();

            if ((event.ctrlKey || event.metaKey) && key === 's') {
                event.preventDefault();
                saveCurrent().catch(handleError);
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === 'n'
                && document.activeElement !== el.noteTitle
            ) {
                event.preventDefault();
                createNote().catch(handleError);
            }
        });

        window.addEventListener('beforeunload', (event) => {
            if (!state.dirty) {
                return;
            }

            event.preventDefault();
            event.returnValue = '';
        });

        const resizeObserver = new ResizeObserver(() => {
            fitEditorToHost();
        });

        resizeObserver.observe(el.editorHost);
    }

    async function boot() {
        setSaveState('Memulai...', 'saving');
        el.saveButton.disabled = true;

        try {
            bindUI();
            await initTinyMCE();
            await loadNotes();
            setSaveState('Tersimpan', 'saved');
        } catch (error) {
            handleError(error);
        }
    }

    boot();
})();
'@

Write-Utf8NoBom -Path $JsPath -Content $js
Ok "JavaScript editor dibuat"

Step "8. PHP LINT"

$lint = & $script:PhpExe -l $ViewPath 2>&1
if ($LASTEXITCODE -ne 0) {
    $lint | ForEach-Object { Write-Host $_ }
    Fail "PHP lint view gagal."
}

Ok "View PHP syntax valid"

Step "9. VERIFY TINYMCE PACKAGE VERSION"

$packageJsonPath = Join-Path $TinyVendor 'package.json'

if (Test-Path $packageJsonPath) {
    try {
        $packageData = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        $tinyVersion = $packageData.version
        Ok "TinyMCE version: $tinyVersion"
    }
    catch {
        Warn "Versi TinyMCE tidak dapat dibaca, tetapi paket tersedia."
        $tinyVersion = 'unknown'
    }
} else {
    $tinyVersion = 'unknown'
    Warn "package.json TinyMCE tidak ditemukan."
}

Step "10. HTTP ASSET VERIFICATION"

$assetUrls = @(
    "$BaseUrl/assets/vendor/tinymce/tinymce.min.js",
    "$BaseUrl/assets/vendor/tinymce/plugins/table/plugin.min.js",
    "$BaseUrl/assets/vendor/tinymce/plugins/codesample/plugin.min.js",
    "$BaseUrl/assets/vendor/tinymce/skins/ui/oxide/skin.min.css",
    "$BaseUrl/assets/css/app.css",
    "$BaseUrl/assets/js/browsernote.js"
)

foreach ($url in $assetUrls) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
        if ($response.StatusCode -ne 200) {
            Fail "Asset merespons HTTP $($response.StatusCode): $url"
        }
        Ok "HTTP 200: $url"
    }
    catch {
        Fail "Asset tidak dapat diakses: $url"
    }
}

Step "11. ROOT PAGE VERIFICATION"

try {
    $page = Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 8
}
catch {
    Fail "BrowserNote root tidak dapat diakses. Pastikan Apache XAMPP aktif."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

$html = $page.Content

$requiredHtml = @(
    'id="noteEditor"',
    'id="noteList"',
    'id="newNoteButton"',
    'id="saveButton"',
    'assets/vendor/tinymce/tinymce.min.js',
    'assets/js/browsernote.js'
)

foreach ($fragment in $requiredHtml) {
    if ($html -notlike "*$fragment*") {
        Fail "Elemen root page tidak ditemukan: $fragment"
    }
}

Ok "Root page BrowserNote terverifikasi"

Step "12. API SMOKE TEST"

try {
    $notes = Invoke-RestMethod `
        -Method GET `
        -Uri "$BaseUrl/api/notes" `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 8 `
        -ErrorAction Stop
}
catch {
    Fail "Notes API tidak dapat diakses setelah Stage 04."
}

if (-not $notes.ok) {
    Fail "Notes API mengembalikan ok=false."
}

Ok "Notes API tetap normal"
Write-Host "       Active notes: $($notes.count)" -ForegroundColor DarkGray

Step "STAGE 04 PASS"

Write-Host ""
Write-Host "Project    : $ProjectRoot" -ForegroundColor White
Write-Host "URL        : $BaseUrl/" -ForegroundColor White
Write-Host "TinyMCE    : $tinyVersion self-hosted" -ForegroundColor White
Write-Host "License    : GPL mode" -ForegroundColor White
Write-Host "Editor     : PASS" -ForegroundColor White
Write-Host "Table      : PASS assets/config" -ForegroundColor White
Write-Host "CodeSample : PASS assets/config" -ForegroundColor White
Write-Host "API        : PASS" -ForegroundColor White
Write-Host ""
Write-Host "BUKA SEKARANG:" -ForegroundColor Cyan
Write-Host "$BaseUrl/" -ForegroundColor Cyan
Write-Host ""
Write-Host "Uji manual Stage 04:" -ForegroundColor Green
Write-Host "1. Catatan awal muncul di sidebar." -ForegroundColor White
Write-Host "2. Toolbar TinyMCE tampil lengkap." -ForegroundColor White
Write-Host "3. Buat tabel 3 x 3." -ForegroundColor White
Write-Host "4. Klik sel tabel dan uji tambah/hapus baris-kolom." -ForegroundColor White
Write-Host "5. Uji merge/split cell dari toolbar kontekstual tabel." -ForegroundColor White
Write-Host "6. Uji Code Sample." -ForegroundColor White
Write-Host "7. Ubah judul/isi lalu klik Simpan." -ForegroundColor White
Write-Host "8. Refresh browser dan pastikan isi tetap ada." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 05 - Autosave + save state yang stabil" -ForegroundColor Green
