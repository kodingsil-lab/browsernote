#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 10A
# QUICK NOTE + SHORTCUTS STANDALONE
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$ViewPath       = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath        = Join-Path $ProjectRoot 'public\assets\css\app.css'
$MainJsPath     = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$SearchJsPath   = Join-Path $ProjectRoot 'public\assets\js\search.js'
$ShortcutJsPath = Join-Path $ProjectRoot 'public\assets\js\shortcuts.js'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage10a_$Stamp"

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
        TimeoutSec  = 10
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $params.ContentType = 'application/json'
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    Invoke-RestMethod @params
}

Step "1. PRECHECK"

foreach ($path in @(
    $ProjectRoot,
    $ViewPath,
    $CssPath,
    $MainJsPath,
    $SearchJsPath
)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)
$searchJs = [System.IO.File]::ReadAllText($SearchJsPath)

if (-not $mainJs.Contains('window.BrowserNoteBridge')) {
    Fail "BrowserNoteBridge Stage 09C tidak ditemukan."
}

if (-not $searchJs.Contains('window.BrowserNoteSearch')) {
    Fail "BrowserNoteSearch Stage 09C tidak ditemukan."
}

Ok "Project ditemukan"
Ok "Stage 09C terverifikasi"
Ok "Tidak perlu patch browsernote.js"

Step "2. BACKUP CURRENT FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $ViewPath,
    $CssPath,
    $ShortcutJsPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. ADD SHORTCUT SCRIPT TO VIEW"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

if (-not $viewText.Contains('assets/js/shortcuts.js')) {
    $searchTag = '<script src="<?= base_url(''assets/js/search.js'') ?>"></script>'
    $shortcutTag = '<script src="<?= base_url(''assets/js/shortcuts.js'') ?>"></script>'

    if ($viewText.Contains($searchTag)) {
        $viewText = $viewText.Replace(
            $searchTag,
            $searchTag + "`r`n" + $shortcutTag
        )
    }
    else {
        $bodyClose = '</body>'

        if (-not $viewText.Contains($bodyClose)) {
            Fail "Tag </body> tidak ditemukan."
        }

        $viewText = $viewText.Replace(
            $bodyClose,
            $shortcutTag + "`r`n" + $bodyClose
        )
    }

    Write-Utf8NoBom -Path $ViewPath -Content $viewText
}

Ok "shortcuts.js ditambahkan ke view"

Step "4. CREATE STANDALONE SHORTCUTS.JS"

$shortcutJs = @'
(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiBase = `${config.baseUrl}/api/notes`;
    const quickOpenKey = 'browsernote.quickOpenNoteId';

    let quickOverlay = null;
    let helpOverlay = null;
    let quickTitle = null;
    let quickBody = null;
    let quickSave = null;

    function bridge() {
        return window.BrowserNoteBridge || null;
    }

    function getCurrentFolderId() {
        const select = document.getElementById('noteFolderSelect');

        if (!select || select.disabled) {
            return null;
        }

        const value = String(select.value || '').trim();

        return value === ''
            ? null
            : Number(value);
    }

    function escapeHtml(value) {
        return String(value)
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function plainTextToHtml(value) {
        const normalized = String(value || '')
            .replace(/\r\n/g, '\n')
            .trim();

        if (normalized === '') {
            return '<p></p>';
        }

        return normalized
            .split(/\n{2,}/)
            .map((paragraph) => {
                const safe = escapeHtml(paragraph)
                    .replace(/\n/g, '<br>');

                return `<p>${safe}</p>`;
            })
            .join('');
    }

    function deriveTitle(title, body) {
        const cleanTitle = String(title || '').trim();

        if (cleanTitle !== '') {
            return cleanTitle.slice(0, 255);
        }

        const firstLine = String(body || '')
            .trim()
            .split(/\r?\n/)[0]
            .trim();

        if (firstLine !== '') {
            return firstLine.slice(0, 90);
        }

        return 'Quick Note';
    }

    async function createQuickNote() {
        const body = quickBody.value;
        const title = deriveTitle(
            quickTitle.value,
            body
        );

        if (
            String(body).trim() === ''
            && String(quickTitle.value).trim() === ''
        ) {
            quickBody.focus();
            return;
        }

        quickSave.disabled = true;
        quickSave.textContent = 'Menyimpan...';

        try {
            const response = await fetch(apiBase, {
                method: 'POST',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    title,
                    content: plainTextToHtml(body),
                    folder_id: getCurrentFolderId(),
                }),
            });

            const data = await response.json();

            if (!response.ok || !data?.ok) {
                throw new Error(
                    data?.message || `HTTP ${response.status}`
                );
            }

            sessionStorage.setItem(
                quickOpenKey,
                String(data.data.id)
            );

            window.location.reload();
        } catch (error) {
            console.error(error);

            quickSave.disabled = false;
            quickSave.textContent =
                'Simpan Quick Note';

            window.alert(
                error?.message
                || 'Quick Note gagal disimpan.'
            );
        }
    }

    function buildQuickNote() {
        if (quickOverlay) {
            return;
        }

        quickOverlay = document.createElement('div');
        quickOverlay.className = 'quick-note-overlay';
        quickOverlay.hidden = true;

        const dialog = document.createElement('section');
        dialog.className = 'quick-note-dialog';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-label', 'Quick Note');

        const header = document.createElement('div');
        header.className = 'quick-note-header';

        const heading = document.createElement('div');
        heading.className = 'quick-note-heading';
        heading.textContent = 'Quick Note';

        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'quick-note-close';
        close.textContent = '×';
        close.title = 'Tutup';
        close.addEventListener('click', closeQuickNote);

        header.append(heading, close);

        quickTitle = document.createElement('input');
        quickTitle.type = 'text';
        quickTitle.className = 'quick-note-title';
        quickTitle.placeholder =
            'Judul opsional — kosongkan untuk memakai baris pertama';
        quickTitle.maxLength = 255;
        quickTitle.autocomplete = 'off';

        quickBody = document.createElement('textarea');
        quickBody.className = 'quick-note-body';
        quickBody.placeholder = 'Tulis catatan singkat...';
        quickBody.spellcheck = true;

        const footer = document.createElement('div');
        footer.className = 'quick-note-footer';

        const hint = document.createElement('div');
        hint.className = 'quick-note-hint';
        hint.textContent =
            'Ctrl+Enter simpan · Esc batal';

        const actions = document.createElement('div');
        actions.className = 'quick-note-actions';

        const cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.className = 'quick-note-secondary';
        cancel.textContent = 'Batal';
        cancel.addEventListener('click', closeQuickNote);

        quickSave = document.createElement('button');
        quickSave.type = 'button';
        quickSave.className = 'quick-note-primary';
        quickSave.textContent = 'Simpan Quick Note';
        quickSave.addEventListener(
            'click',
            createQuickNote
        );

        actions.append(cancel, quickSave);
        footer.append(hint, actions);

        dialog.append(
            header,
            quickTitle,
            quickBody,
            footer
        );

        quickOverlay.appendChild(dialog);
        document.body.appendChild(quickOverlay);

        quickOverlay.addEventListener(
            'mousedown',
            (event) => {
                if (event.target === quickOverlay) {
                    closeQuickNote();
                }
            }
        );

        quickOverlay.addEventListener(
            'keydown',
            (event) => {
                if (event.key === 'Escape') {
                    event.preventDefault();
                    closeQuickNote();
                    return;
                }

                if (
                    (event.ctrlKey || event.metaKey)
                    && event.key === 'Enter'
                ) {
                    event.preventDefault();
                    createQuickNote();
                }
            }
        );
    }

    function openQuickNote() {
        buildQuickNote();

        if (helpOverlay) {
            helpOverlay.hidden = true;
        }

        quickTitle.value = '';
        quickBody.value = '';
        quickSave.disabled = false;
        quickSave.textContent =
            'Simpan Quick Note';

        quickOverlay.hidden = false;

        window.setTimeout(() => {
            quickBody.focus();
        }, 0);
    }

    function closeQuickNote() {
        if (quickOverlay) {
            quickOverlay.hidden = true;
        }
    }

    function buildHelp() {
        if (helpOverlay) {
            return;
        }

        helpOverlay = document.createElement('div');
        helpOverlay.className = 'shortcut-overlay';
        helpOverlay.hidden = true;

        const dialog = document.createElement('section');
        dialog.className = 'shortcut-dialog';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute(
            'aria-label',
            'Keyboard Shortcuts'
        );

        const header = document.createElement('div');
        header.className = 'shortcut-header';

        const heading = document.createElement('div');
        heading.className = 'shortcut-heading';
        heading.textContent = 'Keyboard Shortcuts';

        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'quick-note-close';
        close.textContent = '×';
        close.addEventListener(
            'click',
            closeHelp
        );

        header.append(heading, close);

        const shortcuts = [
            ['Ctrl + N', 'Catatan baru'],
            ['Ctrl + Alt + N', 'Quick Note'],
            ['Ctrl + S', 'Simpan sekarang'],
            ['Ctrl + F', 'Cari judul dan isi'],
            ['Ctrl + Enter', 'Simpan Quick Note'],
            ['Esc', 'Tutup / bersihkan pencarian'],
            ['Ctrl + /', 'Bantuan shortcut'],
        ];

        const list = document.createElement('div');
        list.className = 'shortcut-list';

        for (const [keys, label] of shortcuts) {
            const row = document.createElement('div');
            row.className = 'shortcut-row';

            const key = document.createElement('kbd');
            key.textContent = keys;

            const text = document.createElement('span');
            text.textContent = label;

            row.append(key, text);
            list.appendChild(row);
        }

        dialog.append(header, list);
        helpOverlay.appendChild(dialog);
        document.body.appendChild(helpOverlay);

        helpOverlay.addEventListener(
            'mousedown',
            (event) => {
                if (event.target === helpOverlay) {
                    closeHelp();
                }
            }
        );
    }

    function openHelp() {
        buildHelp();

        if (quickOverlay) {
            quickOverlay.hidden = true;
        }

        helpOverlay.hidden = false;
    }

    function closeHelp() {
        if (helpOverlay) {
            helpOverlay.hidden = true;
        }
    }

    function injectButtons() {
        if (!document.getElementById('quickNoteButton')) {
            const newNoteButton =
                document.getElementById('newNoteButton');

            if (newNoteButton) {
                const quick = document.createElement('button');
                quick.id = 'quickNoteButton';
                quick.type = 'button';
                quick.className = 'quick-note-launcher';

                const label = document.createElement('span');
                label.textContent = 'Quick Note';

                const keys = document.createElement('kbd');
                keys.textContent = 'Ctrl+Alt+N';

                quick.append(label, keys);
                quick.addEventListener(
                    'click',
                    openQuickNote
                );

                newNoteButton.insertAdjacentElement(
                    'afterend',
                    quick
                );
            }
        }

        if (!document.getElementById('shortcutHelpButton')) {
            const footer =
                document.querySelector('.sidebar-footer');

            if (footer) {
                const help = document.createElement('button');
                help.id = 'shortcutHelpButton';
                help.type = 'button';
                help.className = 'shortcut-help-button';

                const label = document.createElement('span');
                label.textContent = 'Shortcut';

                const keys = document.createElement('kbd');
                keys.textContent = 'Ctrl+/';

                help.append(label, keys);
                help.addEventListener(
                    'click',
                    openHelp
                );

                footer.appendChild(help);
            }
        }
    }

    function openQuickCreatedNote() {
        const noteId = Number(
            sessionStorage.getItem(quickOpenKey)
        );

        if (!Number.isInteger(noteId) || noteId < 1) {
            return;
        }

        let attempts = 0;

        const timer = window.setInterval(async () => {
            attempts += 1;

            const app = bridge();

            if (
                app
                && typeof app.openNoteById === 'function'
            ) {
                window.clearInterval(timer);

                try {
                    await app.openNoteById(
                        noteId,
                        'active'
                    );

                    sessionStorage.removeItem(
                        quickOpenKey
                    );
                } catch (error) {
                    console.error(error);
                }

                return;
            }

            if (attempts >= 40) {
                window.clearInterval(timer);
            }
        }, 150);
    }

    document.addEventListener(
        'keydown',
        (event) => {
            const key = event.key.toLowerCase();

            if (
                (event.ctrlKey || event.metaKey)
                && event.altKey
                && key === 'n'
            ) {
                event.preventDefault();
                event.stopPropagation();
                openQuickNote();
                return;
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === '/'
            ) {
                event.preventDefault();
                event.stopPropagation();
                openHelp();
                return;
            }

            if (event.key === 'Escape') {
                if (
                    quickOverlay
                    && !quickOverlay.hidden
                ) {
                    event.preventDefault();
                    closeQuickNote();
                    return;
                }

                if (
                    helpOverlay
                    && !helpOverlay.hidden
                ) {
                    event.preventDefault();
                    closeHelp();
                }
            }
        },
        true
    );

    injectButtons();
    openQuickCreatedNote();

    window.BrowserNoteQuickNote = {
        open: openQuickNote,
        close: closeQuickNote,
    };

    window.BrowserNoteShortcuts = {
        open: openHelp,
        close: closeHelp,
    };
})();
'@

Write-Utf8NoBom -Path $ShortcutJsPath -Content $shortcutJs

Ok "shortcuts.js standalone dibuat"

Step "5. APPEND STAGE 10 CSS"

$cssText = [System.IO.File]::ReadAllText($CssPath)
$cssMarker = '/* BROWSERNOTE_STAGE10_QUICK_NOTE */'

if ($cssText.Contains($cssMarker)) {
    $cssText = $cssText.Substring(
        0,
        $cssText.IndexOf($cssMarker)
    ).TrimEnd()
}

$stage10Css = @'

/* BROWSERNOTE_STAGE10_QUICK_NOTE */

.quick-note-launcher,
.shortcut-help-button {
    width: 100%;
    min-height: 31px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 5px 8px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--surface);
    color: var(--text-soft);
    font-size: 11px;
    cursor: pointer;
}

.quick-note-launcher:hover,
.shortcut-help-button:hover {
    background: var(--surface-hover);
    color: var(--text);
}

.quick-note-launcher kbd,
.shortcut-help-button kbd,
.shortcut-row kbd {
    padding: 2px 5px;
    border: 1px solid var(--border-strong);
    border-bottom-width: 2px;
    border-radius: 4px;
    background: var(--surface-soft);
    color: var(--text-muted);
    font-family: inherit;
    font-size: 9px;
    font-weight: 650;
    white-space: nowrap;
}

.shortcut-help-button {
    margin-top: 5px;
}

.quick-note-overlay,
.shortcut-overlay {
    position: fixed;
    z-index: 1000000;
    inset: 0;
    display: grid;
    place-items: center;
    padding: 20px;
    background: rgba(15, 17, 20, 0.26);
    backdrop-filter: blur(2px);
}

.quick-note-overlay[hidden],
.shortcut-overlay[hidden] {
    display: none;
}

.quick-note-dialog {
    width: min(620px, calc(100vw - 28px));
    max-height: calc(100vh - 40px);
    display: grid;
    grid-template-rows: auto auto minmax(180px, 1fr) auto;
    gap: 10px;
    padding: 14px;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--surface);
    box-shadow: 0 22px 70px rgba(0, 0, 0, 0.22);
}

.quick-note-header,
.shortcut-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
}

.quick-note-heading,
.shortcut-heading {
    font-size: 14px;
    font-weight: 760;
}

.quick-note-close {
    width: 28px;
    height: 28px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--text-muted);
    font-size: 18px;
    cursor: pointer;
}

.quick-note-close:hover {
    background: var(--surface-hover);
    color: var(--text);
}

.quick-note-title,
.quick-note-body {
    width: 100%;
    border: 1px solid var(--border);
    border-radius: 7px;
    outline: none;
    background: var(--surface);
    color: var(--text);
}

.quick-note-title {
    height: 36px;
    padding: 0 10px;
    font-weight: 650;
}

.quick-note-body {
    min-height: 220px;
    padding: 10px;
    resize: vertical;
    line-height: 1.5;
}

.quick-note-title:focus,
.quick-note-body:focus {
    border-color: var(--border-strong);
    box-shadow: 0 0 0 2px rgba(32, 36, 42, 0.06);
}

.quick-note-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
}

.quick-note-hint {
    color: var(--text-muted);
    font-size: 10px;
}

.quick-note-actions {
    display: flex;
    align-items: center;
    gap: 7px;
}

.quick-note-primary,
.quick-note-secondary {
    height: 32px;
    padding: 0 11px;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 650;
    cursor: pointer;
}

.quick-note-primary {
    border: 1px solid var(--accent);
    background: var(--accent);
    color: #ffffff;
}

.quick-note-primary:hover:not(:disabled) {
    background: var(--accent-hover);
}

.quick-note-primary:disabled {
    opacity: 0.55;
    cursor: wait;
}

.quick-note-secondary {
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--text-soft);
}

.quick-note-secondary:hover {
    background: var(--surface-hover);
}

.shortcut-dialog {
    width: min(420px, calc(100vw - 28px));
    padding: 14px;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--surface);
    box-shadow: 0 22px 70px rgba(0, 0, 0, 0.22);
}

.shortcut-list {
    margin-top: 10px;
    display: grid;
    gap: 4px;
}

.shortcut-row {
    min-height: 34px;
    display: grid;
    grid-template-columns: 112px minmax(0, 1fr);
    align-items: center;
    gap: 10px;
    padding: 5px 7px;
    border-radius: 6px;
}

.shortcut-row:hover {
    background: var(--surface-soft);
}

.shortcut-row kbd {
    justify-self: start;
}

.shortcut-row span {
    color: var(--text-soft);
    font-size: 11px;
}
'@

$combinedCss = $cssText.TrimEnd() + "`r`n" + $stage10Css.Trim() + "`r`n"
Write-Utf8NoBom -Path $CssPath -Content $combinedCss

Ok "CSS Quick Note + shortcut dipasang"

Step "6. STATIC VERIFICATION"

$viewVerify = [System.IO.File]::ReadAllText($ViewPath)
$shortcutVerify = [System.IO.File]::ReadAllText($ShortcutJsPath)

if (-not $viewVerify.Contains('assets/js/shortcuts.js')) {
    Fail "shortcuts.js belum dimuat oleh view."
}

foreach ($fragment in @(
    'browsernote.quickOpenNoteId',
    'createQuickNote',
    'Ctrl+Alt+N',
    'window.BrowserNoteQuickNote',
    'window.BrowserNoteShortcuts'
)) {
    if (-not $shortcutVerify.Contains($fragment)) {
        Fail "Marker Stage 10 hilang: $fragment"
    }
}

Ok "Static verification PASS"

Step "7. QUICK NOTE API TEST"

$testId = $null

try {
    $created = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes" -Body @{
        title = '__STAGE10_QUICK_NOTE_TEST__'
        content = '<p>Quick Note standalone test.</p>'
        folder_id = $null
    }

    $testId = [int]$created.data.id

    if ($testId -lt 1) {
        Fail "Quick Note test tidak mendapatkan ID."
    }

    $read = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/notes/$testId"

    if ($read.data.title -ne '__STAGE10_QUICK_NOTE_TEST__') {
        Fail "Quick Note read test gagal."
    }

    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId" | Out-Null
    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId/force" | Out-Null

    $testId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Quick Note API workflow gagal."
}

Ok "Quick Note create PASS"
Ok "Quick Note read PASS"
Ok "Quick Note cleanup PASS"

Step "8. HTTP ASSET VERIFICATION"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8

    $shortcutHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/shortcuts.js" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Root atau shortcuts.js tidak dapat diakses."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if ($shortcutHttp.StatusCode -ne 200) {
    Fail "shortcuts.js tidak HTTP 200."
}

if ($page.Content -notlike '*assets/js/shortcuts.js*') {
    Fail "Root page belum memuat shortcuts.js."
}

if ($shortcutHttp.Content -notlike '*BrowserNoteQuickNote*') {
    Fail "Quick Note tidak tersedia pada shortcuts.js."
}

Ok "HTTP Stage 10 PASS"

Step "STAGE 10A PASS - STAGE 10 COMPLETE"

Write-Host ""
Write-Host "Project        : $ProjectRoot" -ForegroundColor White
Write-Host "URL            : $BaseUrl/" -ForegroundColor White
Write-Host "Quick Note     : PASS" -ForegroundColor White
Write-Host "Main JS patch  : NOT REQUIRED" -ForegroundColor White
Write-Host "Ctrl + N       : catatan baru" -ForegroundColor White
Write-Host "Ctrl + Alt + N : Quick Note" -ForegroundColor White
Write-Host "Ctrl + S       : simpan sekarang" -ForegroundColor White
Write-Host "Ctrl + F       : pencarian aplikasi" -ForegroundColor White
Write-Host "Ctrl + Enter   : simpan Quick Note" -ForegroundColor White
Write-Host "Ctrl + /       : bantuan shortcut" -ForegroundColor White
Write-Host "Esc            : tutup / batal" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 10:" -ForegroundColor Green
Write-Host "1. Tekan Ctrl+Alt+N." -ForegroundColor White
Write-Host "2. Isi teks tanpa judul lalu Ctrl+Enter." -ForegroundColor White
Write-Host "3. Browser reload sekali dan catatan baru harus langsung terbuka." -ForegroundColor White
Write-Host "4. Pastikan baris pertama menjadi judul jika judul dikosongkan." -ForegroundColor White
Write-Host "5. Tekan Ctrl+/ untuk membuka bantuan shortcut." -ForegroundColor White
Write-Host "6. Uji Esc menutup Quick Note dan bantuan." -ForegroundColor White
Write-Host "7. Pastikan Ctrl+F, Ctrl+S, dan Ctrl+N lama tetap normal." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 11 - Export + Backup" -ForegroundColor Green
