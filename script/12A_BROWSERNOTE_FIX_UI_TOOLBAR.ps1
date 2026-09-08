#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 12A
# FIX TINYMCE HORIZONTAL TOOLBAR + CLEAN WRITING UI
# Base colors remain unchanged
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$ViewPath   = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$MainJsPath = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$FixCssPath = Join-Path $ProjectRoot 'public\assets\css\ui-polish-fix.css'
$FixJsPath  = Join-Path $ProjectRoot 'public\assets\js\editor-polish-fix.js'

$Stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir = Join-Path $ProjectRoot "writable\backups\stage12a_$Stamp"

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
    $MainJsPath
)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)

if (-not $mainJs.Contains('tinymce.init')) {
    Fail "TinyMCE config tidak ditemukan."
}

if (-not $mainJs.Contains('BROWSERNOTE_STAGE12_TINYMCE_START')) {
    Warn "Marker Stage 12 tidak ditemukan, tetapi repair tetap dapat dilanjutkan."
}

Ok "Project ditemukan"
Ok "TinyMCE ditemukan"

Step "2. BACKUP CURRENT FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $ViewPath,
    $MainJsPath,
    $FixCssPath,
    $FixJsPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. REMOVE PROBLEMATIC STAGE 12 TINYMCE OPTIONS"

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)

# Keep promotion/branding hidden, but remove statusbar:false because
# it can interact poorly with the existing TinyMCE layout in this build.
$mainJs = $mainJs.Replace(
    "            statusbar: false,`r`n",
    ""
)

$mainJs = $mainJs.Replace(
    "            statusbar: false,`n",
    ""
)

# Replace the oversized toolbar with a compact writing-focused toolbar.
$toolbarPattern = "(?s)\s*toolbar:\s*\[\s*'undo redo \| blocks fontfamily fontsize',\s*'bold italic underline strikethrough \| forecolor backcolor',\s*'alignleft aligncenter alignright alignjustify',\s*'bullist numlist outdent indent \| blockquote',\s*'link codesample table',\s*'removeformat \| searchreplace visualblocks code fullscreen \| help',\s*\]\.join\('\s*\|\s*'\),"

$compactToolbar = @'
            toolbar: [
                'undo redo | blocks',
                'bold italic underline strikethrough | forecolor backcolor',
                'alignleft aligncenter alignright | bullist numlist',
                'outdent indent | blockquote link',
                'codesample table | removeformat',
                'searchreplace code fullscreen'
            ].join(' | '),
'@

$newMainJs = [regex]::Replace(
    $mainJs,
    $toolbarPattern,
    "`r`n" + $compactToolbar.Replace("`n","`r`n").TrimEnd(),
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if ($newMainJs -eq $mainJs) {
    Warn "Toolbar exact pattern tidak ditemukan. Layout tetap diperbaiki melalui CSS repair."
}
else {
    $mainJs = $newMainJs
    Ok "Toolbar TinyMCE disederhanakan"
}

Write-Utf8NoBom -Path $MainJsPath -Content $mainJs

Step "4. ADD REPAIR ASSETS TO VIEW"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

$fixCssTag = '<link rel="stylesheet" href="<?= base_url(''assets/css/ui-polish-fix.css'') ?>">'
$fixJsTag  = '<script src="<?= base_url(''assets/js/editor-polish-fix.js'') ?>"></script>'

if (-not $viewText.Contains('assets/css/ui-polish-fix.css')) {
    $headClose = '</head>'

    if (-not $viewText.Contains($headClose)) {
        Fail "Tag </head> tidak ditemukan."
    }

    $viewText = $viewText.Replace(
        $headClose,
        $fixCssTag + "`r`n" + $headClose
    )
}

if (-not $viewText.Contains('assets/js/editor-polish-fix.js')) {
    $bodyClose = '</body>'

    if (-not $viewText.Contains($bodyClose)) {
        Fail "Tag </body> tidak ditemukan."
    }

    $viewText = $viewText.Replace(
        $bodyClose,
        $fixJsTag + "`r`n" + $bodyClose
    )
}

Write-Utf8NoBom -Path $ViewPath -Content $viewText

Ok "Repair CSS ditambahkan"
Ok "Repair JS ditambahkan"

Step "5. CREATE UI REPAIR CSS"

$fixCss = @'
/* ============================================================
   BrowserNote Stage 12A
   Layout repair only.
   Base colors are intentionally NOT changed.
   ============================================================ */

/* Main interface density */
.app-shell {
    grid-template-columns: 248px minmax(0, 1fr) !important;
}

.sidebar {
    padding: 10px !important;
}

.topbar {
    min-height: 52px !important;
    padding: 7px 12px !important;
    gap: 7px !important;
}

.note-title {
    font-family: "Segoe UI", Arial, sans-serif !important;
    font-size: 15px !important;
    font-weight: 600 !important;
    line-height: 1.25 !important;
}

.note-item-title {
    font-size: 12px !important;
    font-weight: 600 !important;
}

.note-item-meta,
.statusbar,
.save-state {
    font-size: 9.5px !important;
}

.folder-item,
.nav-item {
    font-size: 11px !important;
}

.new-note-button {
    font-size: 12px !important;
}

/* ============================================================
   CRITICAL TINYMCE LAYOUT REPAIR
   Force normal editor stack
   header on top
   editing canvas below
   ============================================================ */

.tox.tox-tinymce {
    display: flex !important;
    flex-direction: column !important;
    align-items: stretch !important;
    width: 100% !important;
    min-width: 0 !important;
}

.tox.tox-tinymce > .tox-editor-container {
    display: flex !important;
    flex: 1 1 auto !important;
    flex-direction: column !important;
    width: 100% !important;
    min-width: 0 !important;
    min-height: 0 !important;
}

.tox .tox-editor-header {
    position: relative !important;
    inset: auto !important;
    top: auto !important;
    right: auto !important;
    bottom: auto !important;
    left: auto !important;

    flex: 0 0 auto !important;
    width: 100% !important;
    max-width: none !important;
    min-width: 0 !important;

    display: block !important;
    float: none !important;

    transform: none !important;
}

.tox .tox-menubar {
    width: 100% !important;
    min-height: 31px !important;
    padding: 2px 8px !important;

    display: flex !important;
    flex-direction: row !important;
    flex-wrap: wrap !important;
    align-items: center !important;
}

.tox .tox-toolbar-overlord {
    width: 100% !important;
    min-width: 0 !important;
    display: block !important;
}

.tox .tox-toolbar,
.tox .tox-toolbar__primary,
.tox .tox-toolbar__overflow {
    width: 100% !important;
    min-width: 0 !important;

    display: flex !important;
    flex-direction: row !important;
    flex-wrap: wrap !important;
    align-items: center !important;
    align-content: flex-start !important;

    overflow: visible !important;
}

.tox .tox-toolbar__group {
    display: flex !important;
    flex: 0 0 auto !important;
    flex-direction: row !important;
    align-items: center !important;

    width: auto !important;
    min-width: 0 !important;

    padding: 2px 3px !important;
}

.tox .tox-sidebar-wrap {
    display: flex !important;
    flex: 1 1 auto !important;
    flex-direction: row !important;

    width: 100% !important;
    min-width: 0 !important;
    min-height: 0 !important;
}

.tox .tox-edit-area {
    flex: 1 1 auto !important;

    width: 100% !important;
    min-width: 0 !important;
    min-height: 0 !important;
}

.tox .tox-edit-area__iframe {
    width: 100% !important;
    min-width: 0 !important;
    height: 100% !important;
}

/* ============================================================
   TOOLBAR DENSITY
   ============================================================ */

.tox .tox-mbtn {
    height: 29px !important;
    padding: 0 7px !important;

    font-family: "Segoe UI", Arial, sans-serif !important;
    font-size: 11.5px !important;
}

.tox .tox-tbtn {
    width: 29px !important;
    height: 29px !important;
    margin: 1px !important;
}

.tox .tox-tbtn--select {
    width: auto !important;
    min-width: 82px !important;
    max-width: 125px !important;
    padding: 0 7px !important;
}

.tox .tox-tbtn__select-label {
    max-width: 95px !important;
    overflow: hidden !important;
    font-size: 10.5px !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}

/* Never show cloud promotion */
.tox .tox-promotion,
.tox .tox-statusbar__branding {
    display: none !important;
}

/* Keep toolbar above canvas, never on the right */
.tox .tox-editor-container {
    grid-template-columns: minmax(0, 1fr) !important;
    grid-template-rows: auto minmax(0, 1fr) auto !important;
}

/* Comfortable width on smaller screens */
@media (max-width: 1100px) {
    .app-shell {
        grid-template-columns: 235px minmax(0, 1fr) !important;
    }

    .tox .tox-tbtn--select {
        min-width: 74px !important;
        max-width: 108px !important;
    }
}
'@

Write-Utf8NoBom -Path $FixCssPath -Content $fixCss
Ok "Horizontal toolbar repair CSS dibuat"

Step "6. CREATE EDITOR DEFAULT REPAIR JS"

$fixJs = @'
(() => {
    'use strict';

    const styleText = `
        body.mce-content-body {
            padding: 22px 30px 72px !important;
            font-family: "Segoe UI", Arial, sans-serif !important;
            font-size: 15px !important;
            font-weight: 400 !important;
            line-height: 1.68 !important;
            letter-spacing: 0 !important;
        }

        body.mce-content-body p {
            margin: 0 0 0.72em;
            font-size: 15px;
            font-weight: 400;
        }

        body.mce-content-body h1 {
            margin: 1.15em 0 0.45em;
            font-size: 23px !important;
            font-weight: 650 !important;
            line-height: 1.28;
        }

        body.mce-content-body h2 {
            margin: 1.1em 0 0.42em;
            font-size: 20px !important;
            font-weight: 650 !important;
            line-height: 1.3;
        }

        body.mce-content-body h3 {
            margin: 1.05em 0 0.4em;
            font-size: 17px !important;
            font-weight: 650 !important;
            line-height: 1.32;
        }

        body.mce-content-body h4 {
            margin: 1em 0 0.38em;
            font-size: 15.5px !important;
            font-weight: 650 !important;
            line-height: 1.35;
        }

        body.mce-content-body strong,
        body.mce-content-body b {
            font-weight: 650;
        }

        body.mce-content-body li {
            margin-bottom: 0.2em;
        }

        body.mce-content-body table {
            font-size: 14px;
        }

        body.mce-content-body th,
        body.mce-content-body td {
            padding: 6px 8px;
        }

        body.mce-content-body pre {
            font-family: Consolas, "Cascadia Code", "Courier New", monospace;
            font-size: 13.5px !important;
            line-height: 1.55;
        }
    `;

    function installStyle(editor) {
        const doc = editor.getDoc();

        if (!doc?.head) {
            return;
        }

        let style = doc.getElementById(
            'browsernote-stage12a-writing-style'
        );

        if (!style) {
            style = doc.createElement('style');
            style.id =
                'browsernote-stage12a-writing-style';

            doc.head.appendChild(style);
        }

        style.textContent = styleText;
    }

    function normalizeEmptyEditor(editor) {
        const text = (
            editor.getContent({ format: 'text' }) || ''
        ).trim();

        if (text !== '') {
            return;
        }

        /*
         * Only normalize truly empty notes.
         * Existing formatting is never rewritten.
         */
        const body = editor.getBody();

        if (!body) {
            return;
        }

        if (
            body.childElementCount === 0
            || (
                body.childElementCount === 1
                && body.firstElementChild?.textContent.trim() === ''
            )
        ) {
            body.innerHTML = '<p><br data-mce-bogus="1"></p>';

            editor.selection.select(
                body.firstElementChild,
                true
            );

            editor.selection.collapse(true);
        }

        try {
            editor.formatter.remove('bold');
            editor.formatter.remove('italic');
            editor.formatter.remove('underline');
            editor.formatter.remove('strikethrough');
        } catch (error) {
            console.debug(
                'Default format cleanup skipped',
                error
            );
        }
    }

    function attach(editor) {
        if (
            !editor
            || editor.__browserNoteStage12AFixed
        ) {
            return;
        }

        editor.__browserNoteStage12AFixed = true;

        installStyle(editor);
        normalizeEmptyEditor(editor);

        editor.on('SetContent', () => {
            installStyle(editor);

            window.setTimeout(() => {
                normalizeEmptyEditor(editor);
            }, 0);
        });

        editor.on('init', () => {
            installStyle(editor);
            normalizeEmptyEditor(editor);
        });
    }

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

        if (attempts >= 80) {
            window.clearInterval(timer);
        }
    }, 125);

    window.BrowserNoteUIFix = {
        refresh() {
            const editor =
                window.tinymce?.get('noteEditor');

            if (editor) {
                installStyle(editor);
                normalizeEmptyEditor(editor);
            }
        },
    };
})();
'@

Write-Utf8NoBom -Path $FixJsPath -Content $fixJs
Ok "Normal paragraph repair JS dibuat"

Step "7. STATIC VERIFICATION"

$viewVerify = [System.IO.File]::ReadAllText($ViewPath)
$cssVerify = [System.IO.File]::ReadAllText($FixCssPath)
$jsVerify = [System.IO.File]::ReadAllText($FixJsPath)

foreach ($fragment in @(
    'assets/css/ui-polish-fix.css',
    'assets/js/editor-polish-fix.js'
)) {
    if (-not $viewVerify.Contains($fragment)) {
        Fail "View marker hilang: $fragment"
    }
}

foreach ($fragment in @(
    'flex-direction: column !important',
    '.tox .tox-editor-header',
    '.tox .tox-toolbar__group',
    '.tox .tox-sidebar-wrap',
    'grid-template-rows: auto minmax(0, 1fr) auto'
)) {
    if (-not $cssVerify.Contains($fragment)) {
        Fail "Repair CSS marker hilang: $fragment"
    }
}

foreach ($fragment in @(
    'font-size: 15px !important',
    'font-weight: 400 !important',
    'normalizeEmptyEditor',
    'browsernote-stage12a-writing-style'
)) {
    if (-not $jsVerify.Contains($fragment)) {
        Fail "Repair JS marker hilang: $fragment"
    }
}

Ok "Static verification PASS"

Step "8. HTTP VERIFICATION"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8

    $cssHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/css/ui-polish-fix.css" `
        -UseBasicParsing `
        -TimeoutSec 8

    $jsHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/editor-polish-fix.js" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Root atau repair assets tidak dapat diakses."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if ($cssHttp.StatusCode -ne 200) {
    Fail "ui-polish-fix.css tidak HTTP 200."
}

if ($jsHttp.StatusCode -ne 200) {
    Fail "editor-polish-fix.js tidak HTTP 200."
}

if ($page.Content -notlike '*ui-polish-fix.css*') {
    Fail "Root belum memuat repair CSS."
}

if ($page.Content -notlike '*editor-polish-fix.js*') {
    Fail "Root belum memuat repair JS."
}

Ok "HTTP repair assets PASS"

Step "STAGE 12A PASS - UI FIX INSTALLED"

Write-Host ""
Write-Host "Project         : $ProjectRoot" -ForegroundColor White
Write-Host "URL             : $BaseUrl/" -ForegroundColor White
Write-Host "Base colors     : UNCHANGED" -ForegroundColor White
Write-Host "TinyMCE toolbar : HORIZONTAL REPAIR" -ForegroundColor White
Write-Host "Toolbar density : compact" -ForegroundColor White
Write-Host "Font selector   : removed from main toolbar where patch matched" -ForegroundColor White
Write-Host "Font size box   : removed from main toolbar where patch matched" -ForegroundColor White
Write-Host "Writing font    : Segoe UI 15 px" -ForegroundColor White
Write-Host "Default weight  : 400 / non-bold" -ForegroundColor White
Write-Host "Heading sizes   : compact" -ForegroundColor White
Write-Host ""
Write-Host "WAJIB setelah script selesai:" -ForegroundColor Green
Write-Host "1. Tutup tab BrowserNote." -ForegroundColor White
Write-Host "2. Buka lagi http://localhost/browsernote/public/" -ForegroundColor White
Write-Host "3. Tekan Ctrl+F5 satu kali." -ForegroundColor White
Write-Host "4. Pastikan toolbar kembali horizontal di atas editor." -ForegroundColor White
Write-Host "5. Buat Catatan Baru." -ForegroundColor White
Write-Host "6. Mulai mengetik. Teks harus normal, 15 px, tidak bold." -ForegroundColor White
Write-Host ""
Write-Host "Jangan lanjut Stage 13 sebelum tampilan ini sudah benar." -ForegroundColor Yellow
