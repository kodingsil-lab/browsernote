#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 12
# UI POLISH - CLEAN TYPOGRAPHY / COMPACT / SAME BASE COLORS
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$ViewPath    = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath     = Join-Path $ProjectRoot 'public\assets\css\app.css'
$MainJsPath  = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$ExportJsPath = Join-Path $ProjectRoot 'public\assets\js\export.js'
$PolishJsPath = Join-Path $ProjectRoot 'public\assets\js\polish.js'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage12_$Stamp"

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

Step "1. PRECHECK"

foreach ($path in @(
    $ProjectRoot,
    $ViewPath,
    $CssPath,
    $MainJsPath,
    $ExportJsPath
)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)

if (-not $mainJs.Contains('tinymce.init')) {
    Fail "Konfigurasi TinyMCE tidak ditemukan."
}

if (-not $mainJs.Contains('window.BrowserNoteBridge')) {
    Fail "BrowserNoteBridge tidak ditemukan."
}

$exportJs = [System.IO.File]::ReadAllText($ExportJsPath)

if (-not $exportJs.Contains('window.BrowserNoteExport')) {
    Fail "Stage 11 belum lengkap."
}

Ok "Project ditemukan"
Ok "Stage 11 terverifikasi"
Ok "TinyMCE config ditemukan"

Step "2. BACKUP CURRENT UI FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $ViewPath,
    $CssPath,
    $MainJsPath,
    $PolishJsPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. POLISH TINYMCE CONFIG"

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)

# Remove Stage 12 options first so rerun remains idempotent.
$stage12Start = '            // BROWSERNOTE_STAGE12_TINYMCE_START'
$stage12End   = '            // BROWSERNOTE_STAGE12_TINYMCE_END'

$stage12Pattern = '(?s)\r?\n?\s*' +
    [regex]::Escape($stage12Start.Trim()) +
    '.*?' +
    [regex]::Escape($stage12End.Trim()) +
    '\r?\n?'

$mainJs = [regex]::Replace(
    $mainJs,
    $stage12Pattern,
    "`r`n"
)

$configBlock = @'
            // BROWSERNOTE_STAGE12_TINYMCE_START
            promotion: false,
            branding: false,
            statusbar: false,
            block_formats: 'Paragraf=p; Judul 1=h1; Judul 2=h2; Judul 3=h3; Judul 4=h4',
            font_size_formats: '12px 13px 14px 15px 16px 18px 20px 22px 24px 28px 32px',
            font_family_formats: 'Segoe UI=Segoe UI,Arial,sans-serif; Arial=Arial,Helvetica,sans-serif; Georgia=Georgia,serif; Times New Roman=Times New Roman,Times,serif; Consolas=Consolas,Cascadia Code,Courier New,monospace',
            // BROWSERNOTE_STAGE12_TINYMCE_END
'@

$configBlock = $configBlock.Replace("`n", "`r`n")

$licenseMarker = "            license_key: 'gpl',"

if ($mainJs.Contains($licenseMarker)) {
    $mainJs = $mainJs.Replace(
        $licenseMarker,
        $licenseMarker + "`r`n" + $configBlock.TrimEnd()
    )

    Ok "TinyMCE clean options dipasang"
}
else {
    Warn "Marker license_key tidak ditemukan. UI tetap dipoles via polish.js."
}

Write-Utf8NoBom -Path $MainJsPath -Content $mainJs

Step "4. ADD POLISH.JS TO VIEW"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

if (-not $viewText.Contains('assets/js/polish.js')) {
    $exportTag = '<script src="<?= base_url(''assets/js/export.js'') ?>"></script>'
    $polishTag = '<script src="<?= base_url(''assets/js/polish.js'') ?>"></script>'

    if ($viewText.Contains($exportTag)) {
        $viewText = $viewText.Replace(
            $exportTag,
            $exportTag + "`r`n" + $polishTag
        )
    }
    else {
        $bodyClose = '</body>'

        if (-not $viewText.Contains($bodyClose)) {
            Fail "Tag </body> tidak ditemukan."
        }

        $viewText = $viewText.Replace(
            $bodyClose,
            $polishTag + "`r`n" + $bodyClose
        )
    }

    Write-Utf8NoBom -Path $ViewPath -Content $viewText
}

Ok "polish.js ditambahkan ke view"

Step "5. CREATE POLISH.JS"

$polishJs = @'
(() => {
    'use strict';

    const editorCss = `
        html {
            background: inherit;
        }

        body.mce-content-body {
            padding: 22px 28px 72px !important;
            font-family: "Segoe UI", Arial, sans-serif !important;
            font-size: 15px !important;
            font-weight: 400 !important;
            line-height: 1.68 !important;
            letter-spacing: 0 !important;
        }

        body.mce-content-body p,
        body.mce-content-body li,
        body.mce-content-body td,
        body.mce-content-body th {
            font-weight: 400;
        }

        body.mce-content-body p {
            margin-top: 0;
            margin-bottom: 0.72em;
        }

        body.mce-content-body h1 {
            margin-top: 1.2em;
            margin-bottom: 0.48em;
            font-size: 23px !important;
            font-weight: 650 !important;
            line-height: 1.28 !important;
        }

        body.mce-content-body h2 {
            margin-top: 1.15em;
            margin-bottom: 0.46em;
            font-size: 20px !important;
            font-weight: 650 !important;
            line-height: 1.3 !important;
        }

        body.mce-content-body h3 {
            margin-top: 1.1em;
            margin-bottom: 0.42em;
            font-size: 17.5px !important;
            font-weight: 650 !important;
            line-height: 1.32 !important;
        }

        body.mce-content-body h4 {
            margin-top: 1em;
            margin-bottom: 0.4em;
            font-size: 15.5px !important;
            font-weight: 650 !important;
            line-height: 1.35 !important;
        }

        body.mce-content-body h1:first-child,
        body.mce-content-body h2:first-child,
        body.mce-content-body h3:first-child,
        body.mce-content-body h4:first-child {
            margin-top: 0;
        }

        body.mce-content-body strong,
        body.mce-content-body b {
            font-weight: 650;
        }

        body.mce-content-body blockquote {
            margin: 0.9em 0;
            padding-top: 0.15em;
            padding-bottom: 0.15em;
        }

        body.mce-content-body ul,
        body.mce-content-body ol {
            margin-top: 0.45em;
            margin-bottom: 0.75em;
            padding-left: 1.65em;
        }

        body.mce-content-body li {
            margin-bottom: 0.24em;
        }

        body.mce-content-body table {
            margin: 0.9em 0;
            font-size: 14px;
        }

        body.mce-content-body th,
        body.mce-content-body td {
            padding: 6px 8px;
        }

        body.mce-content-body pre {
            margin: 0.85em 0;
            padding: 12px 14px;
            font-family: Consolas, "Cascadia Code", "Courier New", monospace;
            font-size: 13.5px !important;
            line-height: 1.55;
        }

        body.mce-content-body code:not(pre code) {
            font-family: Consolas, "Cascadia Code", "Courier New", monospace;
            font-size: 0.92em;
        }
    `;

    function ensureNormalBlankEditor(editor) {
        const text = (
            editor.getContent({ format: 'text' }) || ''
        ).trim();

        if (text !== '') {
            return;
        }

        try {
            editor.execCommand(
                'FormatBlock',
                false,
                'p'
            );

            editor.formatter.remove('bold');
            editor.formatter.remove('italic');
            editor.formatter.remove('underline');
            editor.formatter.remove('strikethrough');
        } catch (error) {
            console.debug(
                'Normal blank editor setup skipped',
                error
            );
        }
    }

    function injectEditorCss(editor) {
        const doc = editor.getDoc();

        if (!doc || !doc.head) {
            return;
        }

        let style = doc.getElementById(
            'browsernote-stage12-editor-style'
        );

        if (!style) {
            style = doc.createElement('style');
            style.id =
                'browsernote-stage12-editor-style';
            doc.head.appendChild(style);
        }

        style.textContent = editorCss;
    }

    function attach(editor) {
        if (!editor || editor.__browserNotePolishBound) {
            return;
        }

        editor.__browserNotePolishBound = true;

        injectEditorCss(editor);
        ensureNormalBlankEditor(editor);

        editor.on('SetContent', () => {
            injectEditorCss(editor);

            window.setTimeout(() => {
                ensureNormalBlankEditor(editor);
            }, 0);
        });

        editor.on('init', () => {
            injectEditorCss(editor);
            ensureNormalBlankEditor(editor);
        });
    }

    function waitForEditor() {
        let attempts = 0;

        const timer = window.setInterval(() => {
            attempts += 1;

            const editor =
                window.tinymce?.get('noteEditor');

            if (editor) {
                attach(editor);
                window.clearInterval(timer);
                return;
            }

            if (attempts >= 60) {
                window.clearInterval(timer);
            }
        }, 150);
    }

    waitForEditor();

    window.BrowserNotePolish = {
        refresh() {
            const editor =
                window.tinymce?.get('noteEditor');

            if (editor) {
                injectEditorCss(editor);
                ensureNormalBlankEditor(editor);
            }
        },
    };
})();
'@

Write-Utf8NoBom -Path $PolishJsPath -Content $polishJs

Ok "polish.js dibuat"

Step "6. APPEND CLEAN UI CSS"

$cssText = [System.IO.File]::ReadAllText($CssPath)
$cssMarker = '/* BROWSERNOTE_STAGE12_UI_POLISH */'

if ($cssText.Contains($cssMarker)) {
    $cssText = $cssText.Substring(
        0,
        $cssText.IndexOf($cssMarker)
    ).TrimEnd()
}

$polishCss = @'

/* BROWSERNOTE_STAGE12_UI_POLISH */
/* Warna dasar sengaja tidak diubah. Hanya typography, spacing, radius, density. */

html,
body,
button,
input,
select,
textarea {
    font-family: "Segoe UI", Arial, sans-serif;
}

body {
    font-size: 13px;
}

.app-shell {
    grid-template-columns: 248px minmax(0, 1fr);
}

.sidebar {
    padding: 10px 10px 8px;
}

.brand-row {
    min-height: 40px;
    margin-bottom: 7px;
}

.brand-wrap {
    gap: 8px;
}

.brand-mark {
    width: 31px;
    height: 31px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 700;
}

.brand {
    font-size: 13.5px;
    font-weight: 650;
    line-height: 1.15;
}

.brand-subtitle {
    margin-top: 1px;
    font-size: 9.5px;
    line-height: 1.15;
}

.icon-button {
    width: 27px;
    height: 27px;
    border-radius: 6px;
    font-size: 14px;
}

.new-note-button {
    min-height: 35px;
    margin-bottom: 7px;
    border-radius: 7px;
    font-size: 12px;
    font-weight: 650;
}

.quick-note-launcher,
.search-box,
.shortcut-help-button,
.export-backup-button {
    min-height: 32px;
    border-radius: 7px;
}

.quick-note-launcher,
.shortcut-help-button,
.export-backup-button {
    font-size: 10.5px;
}

.quick-note-launcher {
    margin-bottom: 7px;
}

.search-box {
    padding-left: 8px;
    padding-right: 6px;
}

.search-box input {
    font-size: 11.5px;
}

.sidebar-section {
    margin-top: 10px;
}

.section-heading {
    min-height: 25px;
    padding-left: 6px;
    padding-right: 5px;
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.045em;
}

.note-list {
    gap: 3px;
}

.note-item {
    padding: 7px 8px;
    border-radius: 7px;
}

.note-item-title {
    font-size: 12px;
    font-weight: 600;
    line-height: 1.3;
}

.note-item-meta {
    margin-top: 2px;
    font-size: 9.5px;
    line-height: 1.25;
}

.folder-item {
    min-height: 30px;
    padding: 4px 7px;
    border-radius: 6px;
    font-size: 11.5px;
}

.folder-more {
    width: 24px;
    height: 24px;
}

.sidebar-footer {
    padding-top: 8px;
}

.nav-item {
    min-height: 31px;
    border-radius: 6px;
    font-size: 11px;
}

.status-nav-count,
.folder-count,
.section-count {
    font-size: 9px;
}

.topbar {
    min-height: 52px;
    padding: 7px 12px;
    gap: 7px;
}

.note-title {
    min-width: 180px;
    font-size: 15px;
    font-weight: 600;
    line-height: 1.25;
}

.note-status-badge {
    padding: 3px 6px;
    font-size: 9px;
    font-weight: 650;
}

.folder-select-wrap {
    gap: 5px;
}

.folder-select-label {
    font-size: 9.5px;
}

.folder-select {
    height: 30px;
    max-width: 150px;
    padding-left: 8px;
    font-size: 10.5px;
    border-radius: 6px;
}

.note-actions {
    gap: 4px;
}

.note-action-button {
    height: 30px;
    padding-left: 8px;
    padding-right: 8px;
    border-radius: 6px;
    font-size: 10px;
    font-weight: 600;
}

.save-state {
    font-size: 10px;
    white-space: nowrap;
}

.save-button {
    height: 30px;
    padding-left: 10px;
    padding-right: 10px;
    border-radius: 6px;
    font-size: 10.5px;
    font-weight: 600;
}

.statusbar {
    min-height: 27px;
    padding-left: 10px;
    padding-right: 10px;
    font-size: 9.5px;
}

.status-right {
    gap: 5px;
}

/* TinyMCE chrome dibuat lebih rapat tanpa menghilangkan fitur. */
.tox.tox-tinymce {
    border-radius: 0;
}

.tox .tox-menubar {
    min-height: 32px;
    padding: 2px 7px;
}

.tox .tox-mbtn {
    height: 28px;
    padding-left: 7px;
    padding-right: 7px;
    font-size: 12px;
}

.tox .tox-toolbar,
.tox .tox-toolbar__overflow,
.tox .tox-toolbar__primary {
    padding-top: 2px;
    padding-bottom: 2px;
}

.tox .tox-toolbar__group {
    padding-left: 3px;
    padding-right: 3px;
}

.tox .tox-tbtn {
    width: 30px;
    height: 30px;
    margin: 1px;
}

.tox .tox-tbtn--select {
    width: auto;
    min-width: 72px;
    max-width: 142px;
    padding-left: 7px;
    padding-right: 7px;
}

.tox .tox-tbtn__select-label {
    font-size: 11px;
}

.tox .tox-promotion,
.tox .tox-statusbar__branding {
    display: none !important;
}

.quick-note-dialog,
.shortcut-dialog,
.export-dialog {
    border-radius: 9px;
}

.quick-note-heading,
.shortcut-heading,
.export-heading {
    font-size: 13.5px;
    font-weight: 650;
}

.quick-note-title {
    font-size: 12px;
    font-weight: 500;
}

.quick-note-body {
    font-family: "Segoe UI", Arial, sans-serif;
    font-size: 13px;
    font-weight: 400;
    line-height: 1.58;
}

.export-card strong,
.backup-card strong {
    font-weight: 600;
}

@media (max-width: 1100px) {
    .app-shell {
        grid-template-columns: 235px minmax(0, 1fr);
    }

    .note-title {
        font-size: 14px;
    }

    .folder-select {
        max-width: 125px;
    }
}
'@

$combinedCss = $cssText.TrimEnd() + "`r`n" + $polishCss.Trim() + "`r`n"
Write-Utf8NoBom -Path $CssPath -Content $combinedCss

Ok "Clean UI CSS dipasang"
Ok "Warna dasar tidak diubah"

Step "7. STATIC VERIFICATION"

$viewVerify = [System.IO.File]::ReadAllText($ViewPath)
$mainVerify = [System.IO.File]::ReadAllText($MainJsPath)
$polishVerify = [System.IO.File]::ReadAllText($PolishJsPath)
$cssVerify = [System.IO.File]::ReadAllText($CssPath)

if (-not $viewVerify.Contains('assets/js/polish.js')) {
    Fail "polish.js belum dimuat oleh view."
}

foreach ($fragment in @(
    'promotion: false',
    'branding: false',
    'statusbar: false',
    "block_formats: 'Paragraf=p",
    "font_size_formats: '12px 13px 14px 15px"
)) {
    if ($mainVerify.Contains("license_key: 'gpl',")) {
        if (-not $mainVerify.Contains($fragment)) {
            Fail "TinyMCE polish option hilang: $fragment"
        }
    }
}

foreach ($fragment in @(
    'font-size: 15px !important',
    'font-weight: 400 !important',
    'ensureNormalBlankEditor',
    'browsernote-stage12-editor-style'
)) {
    if (-not $polishVerify.Contains($fragment)) {
        Fail "Editor polish marker hilang: $fragment"
    }
}

if (-not $cssVerify.Contains('BROWSERNOTE_STAGE12_UI_POLISH')) {
    Fail "UI polish CSS marker hilang."
}

Ok "Static verification PASS"

Step "8. HTTP ASSET VERIFICATION"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8

    $polishHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/polish.js" `
        -UseBasicParsing `
        -TimeoutSec 8

    $cssHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/css/app.css" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Root atau aset Stage 12 tidak dapat diakses melalui Apache."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if ($polishHttp.StatusCode -ne 200) {
    Fail "polish.js tidak HTTP 200."
}

if ($cssHttp.StatusCode -ne 200) {
    Fail "app.css tidak HTTP 200."
}

if ($page.Content -notlike '*assets/js/polish.js*') {
    Fail "Root belum memuat polish.js."
}

if ($polishHttp.Content -notlike '*ensureNormalBlankEditor*') {
    Fail "polish.js belum menyajikan normal-start editor."
}

if ($cssHttp.Content -notlike '*BROWSERNOTE_STAGE12_UI_POLISH*') {
    Fail "CSS polish belum tersedia melalui Apache."
}

Ok "HTTP Stage 12 PASS"

Step "STAGE 12 PASS"

Write-Host ""
Write-Host "Project        : $ProjectRoot" -ForegroundColor White
Write-Host "URL            : $BaseUrl/" -ForegroundColor White
Write-Host "Base colors    : UNCHANGED" -ForegroundColor White
Write-Host "UI typography  : compact / clean" -ForegroundColor White
Write-Host "Sidebar        : 248 px desktop" -ForegroundColor White
Write-Host "Editor body    : Segoe UI 15 px / weight 400" -ForegroundColor White
Write-Host "New note start : Paragraph / normal / non-bold" -ForegroundColor White
Write-Host "Heading sizes  : reduced" -ForegroundColor White
Write-Host "TinyMCE toolbar: compact" -ForegroundColor White
Write-Host "Promotion      : hidden" -ForegroundColor White
Write-Host "Tiny statusbar : removed - app statusbar retained" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 12:" -ForegroundColor Green
Write-Host "1. Hard refresh browser dengan Ctrl+F5." -ForegroundColor White
Write-Host "2. Pastikan warna dasar tetap sama seperti sebelumnya." -ForegroundColor White
Write-Host "3. Buat Catatan Baru dan mulai mengetik." -ForegroundColor White
Write-Host "4. Teks awal harus Paragraf normal, tidak bold, sekitar 15 px." -ForegroundColor White
Write-Host "5. Uji Judul 1-4 dan pastikan ukurannya tidak terlalu besar." -ForegroundColor White
Write-Host "6. Pastikan toolbar lebih rapat tetapi semua fungsi tetap ada." -ForegroundColor White
Write-Host "7. Pastikan tombol Get all features dan statusbar TinyMCE tidak tampil." -ForegroundColor White
Write-Host "8. Uji Quick Note, Search, Export, Arsip, Sampah, Folder, dan autosave." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 13 - Performance + hardening" -ForegroundColor Green
