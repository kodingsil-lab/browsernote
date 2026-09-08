#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 08
# ARCHIVE + TRASH UI
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$ViewPath    = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath     = Join-Path $ProjectRoot 'public\assets\css\app.css'
$JsPath      = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage08_$Stamp"

function Step([string]$Message) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
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

function Resolve-PHP {
    $cmd = Get-Command php -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $xamppPhp = 'C:\xampp\php\php.exe'
    if (Test-Path $xamppPhp) { return $xamppPhp }

    return $null
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

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

foreach ($path in @($ProjectRoot, $ViewPath, $CssPath, $JsPath)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

$jsExisting = [System.IO.File]::ReadAllText($JsPath)

foreach ($marker in @(
    'const folderApiBase',
    'async function createFolder()',
    'async function deleteFolder(folderId)',
    "const DRAFT_PREFIX = 'browsernote.draft.v1.';"
)) {
    if (-not $jsExisting.Contains($marker)) {
        Fail "Stage 07 belum lengkap. Marker hilang: $marker"
    }
}

Ok "Project ditemukan"
Ok "Stage 07 terverifikasi"
Ok "PHP ditemukan: $PhpExe"

Step "2. BACKUP CURRENT UI"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@($ViewPath, $CssPath, $JsPath) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. UPDATE VIEW FOR ARCHIVE + TRASH"

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
                <span id="noteListHeading">CATATAN</span>
                <span class="section-count" id="noteCount">0</span>
            </div>

            <div class="note-list" id="noteList">
                <div class="sidebar-empty">Memuat catatan...</div>
            </div>
        </section>

        <section class="sidebar-section folders-section" id="foldersSection">
            <div class="section-heading">
                <span>FOLDER</span>

                <button
                    class="section-add-button"
                    id="addFolderButton"
                    type="button"
                    title="Buat folder"
                    aria-label="Buat folder"
                >＋</button>
            </div>

            <div class="folder-list" id="folderList">
                <button
                    class="folder-item active"
                    id="allNotesFolder"
                    type="button"
                    data-folder-filter="all"
                >
                    <span class="folder-name">Semua Catatan</span>
                    <span class="folder-count" id="allNotesCount">0</span>
                </button>

                <button
                    class="folder-item"
                    id="unfiledFolder"
                    type="button"
                    data-folder-filter="unfiled"
                >
                    <span class="folder-name">Tanpa Folder</span>
                    <span class="folder-count" id="unfiledCount">0</span>
                </button>

                <div id="dynamicFolderList"></div>
            </div>
        </section>

        <div class="sidebar-footer">
            <button class="nav-item status-nav-item" id="archiveNavButton" type="button">
                <span class="nav-icon">◇</span>
                <span class="status-nav-label">Arsip</span>
                <span class="status-nav-count" id="archiveCount">0</span>
            </button>

            <button class="nav-item status-nav-item" id="trashNavButton" type="button">
                <span class="nav-icon">×</span>
                <span class="status-nav-label">Sampah</span>
                <span class="status-nav-count" id="trashCount">0</span>
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

            <span class="note-status-badge" id="noteStatusBadge">Aktif</span>

            <label class="folder-select-wrap" id="folderSelectWrap" title="Pindahkan catatan ke folder">
                <span class="folder-select-label">Folder</span>
                <select id="noteFolderSelect" class="folder-select" aria-label="Folder catatan">
                    <option value="">Tanpa Folder</option>
                </select>
            </label>

            <div class="note-actions" id="noteActions">
                <button class="note-action-button" id="archiveAction" type="button">Arsipkan</button>
                <button class="note-action-button danger-soft" id="trashAction" type="button">Sampah</button>
                <button class="note-action-button" id="restoreAction" type="button" hidden>Pulihkan</button>
                <button class="note-action-button danger" id="forceDeleteAction" type="button" hidden>Hapus Permanen</button>
            </div>

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

<div class="folder-menu" id="folderMenu" hidden>
    <button type="button" id="renameFolderAction">Ganti nama</button>
    <button type="button" id="deleteFolderAction" class="danger">Hapus folder</button>
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
Ok "View Archive + Trash diperbarui"

Step "4. APPEND ARCHIVE + TRASH CSS"

$cssExisting = [System.IO.File]::ReadAllText($CssPath)
$marker = '/* BROWSERNOTE_STAGE08_ARCHIVE_TRASH */'

if ($cssExisting.Contains($marker)) {
    $cssExisting = $cssExisting.Substring(0, $cssExisting.IndexOf($marker)).TrimEnd()
}

$cssAdd = @'

/* BROWSERNOTE_STAGE08_ARCHIVE_TRASH */

.status-nav-item {
    display: grid;
    grid-template-columns: 18px minmax(0, 1fr) auto;
    align-items: center;
}

.status-nav-item.active {
    background: var(--surface);
    color: var(--text);
    font-weight: 650;
}

.status-nav-count {
    min-width: 18px;
    color: var(--text-muted);
    font-size: 10px;
    text-align: right;
}

.note-status-badge {
    flex: 0 0 auto;
    padding: 4px 7px;
    border: 1px solid var(--border);
    border-radius: 999px;
    background: var(--surface-soft);
    color: var(--text-soft);
    font-size: 10px;
    font-weight: 700;
    white-space: nowrap;
}

.note-status-badge.archived {
    color: #665200;
    background: #fff9db;
    border-color: #e5d98c;
}

.note-status-badge.trashed {
    color: var(--danger);
    background: #fff1f0;
    border-color: #f1c5c1;
}

.note-actions {
    flex: 0 0 auto;
    display: flex;
    align-items: center;
    gap: 5px;
}

.note-action-button {
    height: 30px;
    padding: 0 9px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--surface);
    color: var(--text-soft);
    font-size: 10px;
    font-weight: 650;
    cursor: pointer;
}

.note-action-button:hover:not(:disabled) {
    background: var(--surface-soft);
}

.note-action-button.danger-soft {
    color: #8f2b24;
}

.note-action-button.danger {
    border-color: #e1aaa5;
    color: var(--danger);
}

.note-action-button:disabled {
    opacity: 0.45;
    cursor: default;
}

.workspace.readonly-trash .note-title,
.workspace.readonly-trash .folder-select {
    opacity: 0.7;
}

.mode-empty {
    padding: 16px 9px;
    color: var(--text-muted);
    font-size: 12px;
    line-height: 1.5;
}

@media (max-width: 1150px) {
    .note-action-button {
        padding: 0 7px;
    }

    .note-status-badge {
        display: none;
    }
}

@media (max-width: 980px) {
    .note-actions {
        gap: 3px;
    }

    .note-action-button {
        font-size: 0;
        width: 30px;
        padding: 0;
    }

    #archiveAction::after {
        content: "◇";
        font-size: 13px;
    }

    #trashAction::after {
        content: "×";
        font-size: 15px;
    }

    #restoreAction::after {
        content: "↶";
        font-size: 14px;
    }

    #forceDeleteAction::after {
        content: "×";
        font-size: 15px;
    }
}
'@

Write-Utf8NoBom -Path $CssPath -Content ($cssExisting.TrimEnd() + "`r`n" + $cssAdd.Trim() + "`r`n")
Ok "CSS Archive + Trash ditambahkan"

Step "5. INSTALL STAGE 08 JAVASCRIPT"

$js = @'
(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiBase = `${config.baseUrl}/api/notes`;
    const folderApiBase = `${config.baseUrl}/api/folders`;

    const AUTOSAVE_DELAY = 700;
    const LOCAL_DRAFT_DELAY = 180;
    const DRAFT_PREFIX = 'browsernote.draft.v1.';

    const state = {
        editor: null,

        collections: {
            active: [],
            archived: [],
            trash: [],
        },

        folders: [],

        mode: 'active',
        folderFilter: 'all',

        currentId: null,
        currentNote: null,
        folderMenuId: null,

        dirty: false,
        loading: false,
        saving: false,

        editVersion: 0,
        lastSavedVersion: 0,
        savePromise: null,
        autosaveTimer: null,

        localDraftTimer: null,
        localDraftErrorShown: false,

        toastTimer: null,
    };

    const el = {
        appShell: document.getElementById('appShell'),
        workspace: document.querySelector('.workspace'),
        collapseSidebar: document.getElementById('collapseSidebar'),
        showSidebar: document.getElementById('showSidebar'),

        newNoteButton: document.getElementById('newNoteButton'),
        noteListHeading: document.getElementById('noteListHeading'),
        noteList: document.getElementById('noteList'),
        noteCount: document.getElementById('noteCount'),

        foldersSection: document.getElementById('foldersSection'),
        allNotesFolder: document.getElementById('allNotesFolder'),
        allNotesCount: document.getElementById('allNotesCount'),
        unfiledFolder: document.getElementById('unfiledFolder'),
        unfiledCount: document.getElementById('unfiledCount'),
        dynamicFolderList: document.getElementById('dynamicFolderList'),
        addFolderButton: document.getElementById('addFolderButton'),

        archiveNavButton: document.getElementById('archiveNavButton'),
        archiveCount: document.getElementById('archiveCount'),
        trashNavButton: document.getElementById('trashNavButton'),
        trashCount: document.getElementById('trashCount'),

        noteTitle: document.getElementById('noteTitle'),
        noteStatusBadge: document.getElementById('noteStatusBadge'),
        folderSelectWrap: document.getElementById('folderSelectWrap'),
        noteFolderSelect: document.getElementById('noteFolderSelect'),

        archiveAction: document.getElementById('archiveAction'),
        trashAction: document.getElementById('trashAction'),
        restoreAction: document.getElementById('restoreAction'),
        forceDeleteAction: document.getElementById('forceDeleteAction'),

        saveState: document.getElementById('saveState'),
        saveButton: document.getElementById('saveButton'),

        editorHost: document.getElementById('editorHost'),
        currentNoteInfo: document.getElementById('currentNoteInfo'),

        wordCount: document.getElementById('wordCount'),
        charCount: document.getElementById('charCount'),

        folderMenu: document.getElementById('folderMenu'),
        renameFolderAction: document.getElementById('renameFolderAction'),
        deleteFolderAction: document.getElementById('deleteFolderAction'),

        toast: document.getElementById('toast'),
    };

    function setSaveState(text, type = 'ready') {
        el.saveState.textContent = text;
        el.saveState.dataset.state = type;
    }

    function currentClock() {
        return new Intl.DateTimeFormat('id-ID', {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
        }).format(new Date());
    }

    function showToast(message, duration = 2200) {
        el.toast.textContent = message;
        el.toast.classList.add('show');

        window.clearTimeout(state.toastTimer);
        state.toastTimer = window.setTimeout(() => {
            el.toast.classList.remove('show');
        }, duration);
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

    function modeStatusQuery(mode = state.mode) {
        if (mode === 'archived') {
            return 'archived';
        }

        if (mode === 'trash') {
            return 'trash';
        }

        return 'active';
    }

    function currentCollection() {
        return state.collections[state.mode] || [];
    }

    function isTrashMode() {
        return state.mode === 'trash';
    }

    function canEditCurrent() {
        return Boolean(state.currentId) && !isTrashMode();
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

    /*
     * LOCAL RECOVERY
     */

    function draftKey(noteId) {
        return `${DRAFT_PREFIX}${Number(noteId)}`;
    }

    function readLocalDraft(noteId) {
        if (!noteId) {
            return null;
        }

        try {
            const raw = localStorage.getItem(draftKey(noteId));

            if (!raw) {
                return null;
            }

            const draft = JSON.parse(raw);

            if (
                !draft
                || Number(draft.noteId) !== Number(noteId)
                || typeof draft.title !== 'string'
                || typeof draft.content !== 'string'
            ) {
                localStorage.removeItem(draftKey(noteId));
                return null;
            }

            return draft;
        } catch (error) {
            console.warn('Local draft read failed', error);
            return null;
        }
    }

    function clearLocalDraft(noteId) {
        if (!noteId) {
            return;
        }

        try {
            localStorage.removeItem(draftKey(noteId));
        } catch (error) {
            console.warn('Local draft cleanup failed', error);
        }
    }

    function persistLocalDraftNow() {
        if (
            state.loading
            || !state.currentId
            || !state.editor
            || !state.dirty
            || isTrashMode()
        ) {
            return false;
        }

        const draft = {
            version: 1,
            noteId: Number(state.currentId),
            title: el.noteTitle.value || '',
            content: state.editor.getContent(),
            folderId: el.noteFolderSelect.value || null,
            editVersion: state.editVersion,
            baseUpdatedAt: state.currentNote?.updated_at || null,
            savedAt: Date.now(),
        };

        try {
            localStorage.setItem(
                draftKey(state.currentId),
                JSON.stringify(draft)
            );

            state.localDraftErrorShown = false;
            return true;
        } catch (error) {
            console.error('Local draft write failed', error);

            if (!state.localDraftErrorShown) {
                state.localDraftErrorShown = true;
                showToast(
                    'Draft lokal gagal disimpan. Periksa penyimpanan browser.',
                    4200
                );
            }

            return false;
        }
    }

    function clearLocalDraftTimer() {
        if (state.localDraftTimer !== null) {
            window.clearTimeout(state.localDraftTimer);
            state.localDraftTimer = null;
        }
    }

    function scheduleLocalDraft() {
        clearLocalDraftTimer();

        if (
            state.loading
            || !state.currentId
            || !state.editor
            || !state.dirty
            || isTrashMode()
        ) {
            return;
        }

        state.localDraftTimer = window.setTimeout(() => {
            state.localDraftTimer = null;
            persistLocalDraftNow();
        }, LOCAL_DRAFT_DELAY);
    }

    function localDraftMatchesServer(draft, note) {
        return (
            (draft.title || '') === (note.title || '')
            && (draft.content || '') === (note.content || '')
            && String(draft.folderId || '') === String(note.folder_id || '')
        );
    }

    function shouldRecoverDraft(draft, note) {
        if (!draft || isTrashMode()) {
            return false;
        }

        if (localDraftMatchesServer(draft, note)) {
            clearLocalDraft(note.id);
            return false;
        }

        if (
            draft.baseUpdatedAt
            && note.updated_at
            && draft.baseUpdatedAt === note.updated_at
        ) {
            return true;
        }

        if (!draft.baseUpdatedAt) {
            return true;
        }

        return window.confirm(
            'Ditemukan draft lokal yang belum tersimpan, tetapi versi server juga sudah berubah. ' +
            'Pilih OK untuk memulihkan draft lokal. Pilih Cancel untuk memakai versi server.'
        );
    }

    function applyRecoveredDraft(draft, note) {
        state.currentId = Number(note.id);
        state.currentNote = note;

        state.editVersion = Math.max(
            1,
            Number(draft.editVersion) || 1
        );
        state.lastSavedVersion = 0;
        state.dirty = true;

        el.noteTitle.value = draft.title || '';
        el.noteFolderSelect.value = draft.folderId
            ? String(draft.folderId)
            : '';

        state.editor.setContent(draft.content || '');
        state.editor.undoManager.clear();

        updateCounters();
        setSaveState('Draft lokal dipulihkan', 'dirty');
        el.saveButton.disabled = false;

        persistLocalDraftNow();
        scheduleAutosave();

        showToast(
            'Draft lokal yang belum tersimpan berhasil dipulihkan.',
            3600
        );
    }

    /*
     * AUTOSAVE
     */

    function clearAutosaveTimer() {
        if (state.autosaveTimer !== null) {
            window.clearTimeout(state.autosaveTimer);
            state.autosaveTimer = null;
        }
    }

    function scheduleAutosave() {
        if (
            state.loading
            || !state.currentId
            || !state.editor
            || !state.dirty
            || isTrashMode()
        ) {
            return;
        }

        clearAutosaveTimer();

        state.autosaveTimer = window.setTimeout(() => {
            state.autosaveTimer = null;

            saveCurrent({
                quiet: true,
                automatic: true,
            }).catch(handleError);
        }, AUTOSAVE_DELAY);
    }

    function markDirty() {
        if (
            state.loading
            || !state.currentId
            || isTrashMode()
        ) {
            return;
        }

        state.editVersion += 1;
        state.dirty = true;

        setSaveState('Belum tersimpan', 'dirty');
        el.saveButton.disabled = false;

        updateCounters();
        scheduleLocalDraft();
        scheduleAutosave();
    }

    function setClean(savedText = 'Tersimpan') {
        state.dirty = false;
        state.lastSavedVersion = state.editVersion;

        clearLocalDraftTimer();
        clearLocalDraft(state.currentId);

        setSaveState(savedText, 'saved');
        el.saveButton.disabled = true;

        if (state.editor) {
            state.editor.setDirty(false);
        }
    }

    /*
     * COLLECTIONS + MODE
     */

    async function loadCollections() {
        const [active, archived, trash] = await Promise.all([
            request(`${apiBase}?status=active`),
            request(`${apiBase}?status=archived`),
            request(`${apiBase}?status=trash`),
        ]);

        state.collections.active = Array.isArray(active.data)
            ? active.data
            : [];

        state.collections.archived = Array.isArray(archived.data)
            ? archived.data
            : [];

        state.collections.trash = Array.isArray(trash.data)
            ? trash.data
            : [];

        updateStatusCounts();
    }

    function updateStatusCounts() {
        el.archiveCount.textContent = String(
            state.collections.archived.length
        );

        el.trashCount.textContent = String(
            state.collections.trash.length
        );

        el.allNotesCount.textContent = String(
            state.collections.active.length
        );

        const unfiled = state.collections.active.filter(
            (note) => !note.folder_id
        ).length;

        el.unfiledCount.textContent = String(unfiled);
    }

    function setEditorReadonly(readonly) {
        el.noteTitle.readOnly = readonly;
        el.noteFolderSelect.disabled = readonly;
        el.saveButton.hidden = readonly;

        el.workspace.classList.toggle(
            'readonly-trash',
            readonly
        );

        if (state.editor?.mode?.set) {
            state.editor.mode.set(
                readonly ? 'readonly' : 'design'
            );
        }
    }

    function updateModeUI() {
        const archived = state.mode === 'archived';
        const trash = state.mode === 'trash';
        const active = state.mode === 'active';

        el.archiveNavButton.classList.toggle('active', archived);
        el.trashNavButton.classList.toggle('active', trash);

        el.foldersSection.hidden = !active;
        el.addFolderButton.disabled = !active;
        el.newNoteButton.disabled = !active;

        el.noteListHeading.textContent = active
            ? 'CATATAN'
            : archived
                ? 'ARSIP'
                : 'SAMPAH';

        el.noteStatusBadge.textContent = active
            ? 'Aktif'
            : archived
                ? 'Arsip'
                : 'Sampah';

        el.noteStatusBadge.className = 'note-status-badge';

        if (archived) {
            el.noteStatusBadge.classList.add('archived');
        }

        if (trash) {
            el.noteStatusBadge.classList.add('trashed');
        }

        el.archiveAction.hidden = !active;
        el.trashAction.hidden = trash;
        el.restoreAction.hidden = active;
        el.forceDeleteAction.hidden = !trash;

        setEditorReadonly(trash);

        if (trash) {
            setSaveState('Read-only', 'ready');
        }

        setActiveFolderButton();
    }

    async function switchMode(mode) {
        if (!['active', 'archived', 'trash'].includes(mode)) {
            return;
        }

        if (state.mode === mode) {
            return;
        }

        await flushPendingSave();

        state.mode = mode;
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        const list = currentVisibleNotes();

        if (list.length > 0) {
            await openNote(Number(list[0].id));
        } else {
            clearCurrentEditor();
        }
    }

    function clearCurrentEditor() {
        clearAutosaveTimer();
        clearLocalDraftTimer();

        state.currentId = null;
        state.currentNote = null;
        state.dirty = false;

        el.noteTitle.value = '';
        el.noteFolderSelect.value = '';
        el.currentNoteInfo.textContent = 'Tidak ada catatan';

        if (state.editor) {
            state.editor.setContent('');
            state.editor.undoManager.clear();
        }

        el.wordCount.textContent = '0 kata';
        el.charCount.textContent = '0 karakter';
        el.saveButton.disabled = true;

        updateModeUI();
    }

    /*
     * FOLDERS
     */

    function folderNameById(folderId) {
        if (!folderId) {
            return 'Tanpa Folder';
        }

        const folder = state.folders.find(
            (item) => Number(item.id) === Number(folderId)
        );

        return folder?.name || 'Tanpa Folder';
    }

    function renderFolderSelect() {
        const currentValue = state.currentNote?.folder_id
            ? String(state.currentNote.folder_id)
            : '';

        el.noteFolderSelect.innerHTML = '';

        const none = document.createElement('option');
        none.value = '';
        none.textContent = 'Tanpa Folder';
        el.noteFolderSelect.appendChild(none);

        for (const folder of state.folders) {
            const option = document.createElement('option');
            option.value = String(folder.id);
            option.textContent = folder.name;
            el.noteFolderSelect.appendChild(option);
        }

        el.noteFolderSelect.value = currentValue;
    }

    function setActiveFolderButton() {
        document
            .querySelectorAll('[data-folder-filter]')
            .forEach((button) => {
                button.classList.toggle(
                    'active',
                    state.mode === 'active'
                    && String(button.dataset.folderFilter)
                        === String(state.folderFilter)
                );
            });
    }

    function renderFolders() {
        el.dynamicFolderList.innerHTML = '';

        for (const folder of state.folders) {
            const row = document.createElement('div');
            row.className = 'folder-item-row';

            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'folder-item';
            button.dataset.folderFilter = String(folder.id);

            const name = document.createElement('span');
            name.className = 'folder-name';
            name.textContent = folder.name;

            const count = document.createElement('span');
            count.className = 'folder-count';
            count.textContent = String(
                state.collections.active.filter(
                    (note) => Number(note.folder_id) === Number(folder.id)
                ).length
            );

            button.append(name, count);

            button.addEventListener('click', async () => {
                try {
                    if (state.mode !== 'active') {
                        await switchMode('active');
                    }

                    state.folderFilter = String(folder.id);
                    setActiveFolderButton();
                    renderNotes();

                    const list = currentVisibleNotes();

                    if (
                        state.currentId
                        && list.some(
                            (note) => Number(note.id) === Number(state.currentId)
                        )
                    ) {
                        return;
                    }

                    if (list.length > 0) {
                        await openNote(Number(list[0].id));
                    } else {
                        clearCurrentEditor();
                    }
                } catch (error) {
                    handleError(error);
                }
            });

            const more = document.createElement('button');
            more.type = 'button';
            more.className = 'folder-more';
            more.textContent = '⋯';
            more.title = `Kelola ${folder.name}`;

            more.addEventListener('click', (event) => {
                event.stopPropagation();
                openFolderMenu(folder.id, more);
            });

            row.append(button, more);
            el.dynamicFolderList.appendChild(row);
        }

        updateStatusCounts();
        setActiveFolderButton();
        renderFolderSelect();
    }

    async function loadFolders() {
        const response = await request(folderApiBase);
        state.folders = Array.isArray(response.data)
            ? response.data
            : [];

        renderFolders();
    }

    async function createFolder() {
        const name = window.prompt('Nama folder baru');

        if (name === null) {
            return;
        }

        const clean = name.trim();

        if (!clean) {
            showToast('Nama folder tidak boleh kosong');
            return;
        }

        const response = await request(folderApiBase, {
            method: 'POST',
            body: JSON.stringify({ name: clean }),
        });

        await loadFolders();

        state.mode = 'active';
        state.folderFilter = String(response.data.id);

        updateModeUI();
        renderFolders();
        renderNotes();

        showToast('Folder dibuat');
    }

    function openFolderMenu(folderId, anchor) {
        state.folderMenuId = Number(folderId);

        const rect = anchor.getBoundingClientRect();
        el.folderMenu.hidden = false;

        const width = 150;
        const left = Math.max(
            8,
            Math.min(
                window.innerWidth - width - 8,
                rect.right - width
            )
        );

        const top = Math.min(
            window.innerHeight - 90,
            rect.bottom + 4
        );

        el.folderMenu.style.left = `${left}px`;
        el.folderMenu.style.top = `${top}px`;
    }

    function closeFolderMenu() {
        el.folderMenu.hidden = true;
        state.folderMenuId = null;
    }

    async function renameFolder(folderId) {
        const folder = state.folders.find(
            (item) => Number(item.id) === Number(folderId)
        );

        if (!folder) {
            return;
        }

        const name = window.prompt(
            'Nama folder',
            folder.name
        );

        if (name === null) {
            return;
        }

        const clean = name.trim();

        if (!clean) {
            showToast('Nama folder tidak boleh kosong');
            return;
        }

        await request(`${folderApiBase}/${folderId}`, {
            method: 'PATCH',
            body: JSON.stringify({ name: clean }),
        });

        await Promise.all([
            loadFolders(),
            loadCollections(),
        ]);

        renderFolders();
        renderNotes();

        showToast('Nama folder diperbarui');
    }

    async function deleteFolder(folderId) {
        const folder = state.folders.find(
            (item) => Number(item.id) === Number(folderId)
        );

        if (!folder) {
            return;
        }

        const confirmed = window.confirm(
            `Hapus folder "${folder.name}"?\n\nCatatan di dalam folder tidak akan dihapus. Catatan akan dipindahkan ke Tanpa Folder.`
        );

        if (!confirmed) {
            return;
        }

        await flushPendingSave();

        await request(`${folderApiBase}/${folderId}`, {
            method: 'DELETE',
        });

        if (String(state.folderFilter) === String(folderId)) {
            state.folderFilter = 'all';
        }

        await Promise.all([
            loadFolders(),
            loadCollections(),
        ]);

        if (state.currentId) {
            const refreshed = state.collections.active.find(
                (note) => Number(note.id) === Number(state.currentId)
            );

            if (refreshed) {
                state.currentNote = {
                    ...state.currentNote,
                    ...refreshed,
                };
            }
        }

        renderFolders();
        renderNotes();

        showToast('Folder dihapus');
    }

    /*
     * NOTES
     */

    function currentVisibleNotes() {
        const collection = currentCollection();

        if (state.mode !== 'active') {
            return collection;
        }

        if (state.folderFilter === 'all') {
            return collection;
        }

        if (state.folderFilter === 'unfiled') {
            return collection.filter(
                (note) => !note.folder_id
            );
        }

        const folderId = Number(state.folderFilter);

        return collection.filter(
            (note) => Number(note.folder_id) === folderId
        );
    }

    function renderNotes() {
        const visibleNotes = currentVisibleNotes();

        el.noteList.innerHTML = '';
        el.noteCount.textContent = String(visibleNotes.length);

        if (visibleNotes.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'mode-empty';

            empty.textContent = state.mode === 'active'
                ? 'Tidak ada catatan pada bagian ini.'
                : state.mode === 'archived'
                    ? 'Belum ada catatan di Arsip.'
                    : 'Sampah kosong.';

            el.noteList.appendChild(empty);
            return;
        }

        for (const note of visibleNotes) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'note-item';

            if (Number(note.id) === Number(state.currentId)) {
                button.classList.add('active');
            }

            const title = document.createElement('div');
            title.className = 'note-item-title';
            title.textContent = note.title || 'Catatan tanpa judul';

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
                    await flushPendingSave();
                    await openNote(id);
                } catch (error) {
                    handleError(error);
                }
            });

            el.noteList.appendChild(button);
        }
    }

    async function openNote(id) {
        if (!state.editor) {
            return;
        }

        clearAutosaveTimer();
        clearLocalDraftTimer();

        state.loading = true;
        setSaveState('Memuat...', 'saving');

        try {
            const response = await request(`${apiBase}/${id}`);
            const note = response.data;

            state.currentId = Number(note.id);
            state.currentNote = note;

            state.editVersion = 0;
            state.lastSavedVersion = 0;
            state.dirty = false;

            renderFolderSelect();

            const localDraft = isTrashMode()
                ? null
                : readLocalDraft(note.id);

            if (
                localDraft
                && shouldRecoverDraft(localDraft, note)
            ) {
                applyRecoveredDraft(localDraft, note);
            } else {
                if (localDraft) {
                    clearLocalDraft(note.id);
                }

                el.noteTitle.value = note.title || '';
                el.noteFolderSelect.value = note.folder_id
                    ? String(note.folder_id)
                    : '';

                state.editor.setContent(note.content || '');
                state.editor.undoManager.clear();

                updateCounters();

                if (!isTrashMode()) {
                    setClean('Tersimpan');
                }
            }

            el.currentNoteInfo.textContent =
                `#${note.id} · ${folderNameById(note.folder_id)}`;

            updateModeUI();
            renderNotes();

            window.setTimeout(() => {
                state.editor.focus();
            }, 0);
        } finally {
            state.loading = false;
        }
    }

    async function createNote() {
        if (state.mode !== 'active') {
            await switchMode('active');
        }

        await flushPendingSave();

        el.newNoteButton.disabled = true;
        setSaveState('Membuat...', 'saving');

        let folderId = null;

        if (
            state.folderFilter !== 'all'
            && state.folderFilter !== 'unfiled'
        ) {
            folderId = Number(state.folderFilter);
        }

        try {
            const response = await request(apiBase, {
                method: 'POST',
                body: JSON.stringify({
                    title: 'Catatan tanpa judul',
                    content: '<p></p>',
                    folder_id: folderId,
                }),
            });

            await loadCollections();
            await loadFolders();

            renderFolders();
            renderNotes();

            await openNote(Number(response.data.id));

            showToast('Catatan baru dibuat');

            return response.data;
        } finally {
            el.newNoteButton.disabled = false;
        }
    }

    async function performSave({
        quiet = false,
        automatic = false,
    } = {}) {
        if (
            !state.currentId
            || !state.editor
            || !state.dirty
            || isTrashMode()
        ) {
            return;
        }

        clearLocalDraftTimer();
        persistLocalDraftNow();

        const noteId = Number(state.currentId);
        const versionAtStart = state.editVersion;

        const title = el.noteTitle.value.trim()
            || 'Catatan tanpa judul';

        const content = state.editor.getContent();

        const folderId = el.noteFolderSelect.value
            ? Number(el.noteFolderSelect.value)
            : null;

        state.saving = true;
        el.saveButton.disabled = true;
        setSaveState('Menyimpan...', 'saving');

        try {
            const response = await request(
                `${apiBase}/${noteId}`,
                {
                    method: 'PATCH',
                    body: JSON.stringify({
                        title,
                        content,
                        folder_id: folderId,
                    }),
                }
            );

            if (Number(state.currentId) !== noteId) {
                return;
            }

            state.currentNote = response.data;

            await loadCollections();
            await loadFolders();

            renderFolders();
            renderNotes();

            el.currentNoteInfo.textContent =
                `#${response.data.id} · ${folderNameById(response.data.folder_id)}`;

            if (state.editVersion === versionAtStart) {
                el.noteTitle.value = response.data.title || title;

                setClean(
                    automatic
                        ? `Tersimpan otomatis ${currentClock()}`
                        : `Tersimpan ${currentClock()}`
                );
            } else {
                state.dirty = true;
                el.saveButton.disabled = false;
                setSaveState('Ada perubahan baru', 'dirty');

                persistLocalDraftNow();
                scheduleAutosave();
            }

            updateCounters();

            if (!quiet && !automatic) {
                showToast('Catatan tersimpan');
            }
        } catch (error) {
            if (Number(state.currentId) === noteId) {
                state.dirty = true;
                el.saveButton.disabled = false;

                persistLocalDraftNow();

                setSaveState(
                    'Gagal menyimpan · draft lokal aman',
                    'error'
                );
            }

            throw error;
        } finally {
            state.saving = false;
        }
    }

    function saveCurrent(options = {}) {
        clearAutosaveTimer();

        if (state.savePromise) {
            return state.savePromise.then(async () => {
                if (state.dirty) {
                    return saveCurrent(options);
                }
            });
        }

        state.savePromise = performSave(options)
            .finally(() => {
                state.savePromise = null;
            });

        return state.savePromise;
    }

    async function flushPendingSave() {
        clearAutosaveTimer();
        clearLocalDraftTimer();

        if (isTrashMode()) {
            return;
        }

        if (state.dirty) {
            persistLocalDraftNow();
        }

        if (state.savePromise) {
            await state.savePromise;
        }

        if (state.dirty) {
            await saveCurrent({
                quiet: true,
                automatic: true,
            });
        }

        if (state.savePromise) {
            await state.savePromise;
        }
    }

    /*
     * ARCHIVE + TRASH ACTIONS
     */

    async function archiveCurrent() {
        if (!state.currentId || state.mode !== 'active') {
            return;
        }

        await flushPendingSave();

        const id = Number(state.currentId);

        await request(`${apiBase}/${id}/archive`, {
            method: 'POST',
        });

        clearLocalDraft(id);

        await loadCollections();

        state.mode = 'archived';
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(id);

        showToast('Catatan diarsipkan');
    }

    async function moveCurrentToTrash() {
        if (!state.currentId || state.mode === 'trash') {
            return;
        }

        await flushPendingSave();

        const id = Number(state.currentId);

        await request(`${apiBase}/${id}`, {
            method: 'DELETE',
        });

        clearLocalDraft(id);

        await loadCollections();

        state.mode = 'trash';
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(id);

        showToast('Catatan dipindahkan ke Sampah');
    }

    async function restoreCurrent() {
        if (!state.currentId) {
            return;
        }

        const id = Number(state.currentId);

        if (state.mode === 'archived') {
            await flushPendingSave();

            await request(
                `${apiBase}/${id}/restore-archive`,
                { method: 'POST' }
            );
        } else if (state.mode === 'trash') {
            await request(
                `${apiBase}/${id}/restore-trash`,
                { method: 'POST' }
            );
        } else {
            return;
        }

        clearLocalDraft(id);

        await loadCollections();

        state.mode = 'active';
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(id);

        showToast('Catatan dipulihkan');
    }

    async function forceDeleteCurrent() {
        if (
            !state.currentId
            || state.mode !== 'trash'
        ) {
            return;
        }

        const id = Number(state.currentId);
        const title = state.currentNote?.title
            || 'Catatan tanpa judul';

        const confirmed = window.confirm(
            `Hapus permanen "${title}"?\n\nTindakan ini tidak dapat dibatalkan.`
        );

        if (!confirmed) {
            return;
        }

        await request(
            `${apiBase}/${id}/force`,
            { method: 'DELETE' }
        );

        clearLocalDraft(id);

        await loadCollections();

        renderNotes();
        updateStatusCounts();

        const remaining = currentVisibleNotes();

        if (remaining.length > 0) {
            await openNote(Number(remaining[0].id));
        } else {
            clearCurrentEditor();
        }

        showToast('Catatan dihapus permanen');
    }

    function handleError(error) {
        console.error(error);

        if (state.dirty && !isTrashMode()) {
            persistLocalDraftNow();

            setSaveState(
                'Gagal menyimpan · draft lokal aman',
                'error'
            );
        } else {
            setSaveState('Terjadi kesalahan', 'error');
        }

        showToast(
            error?.message || 'Terjadi kesalahan.'
        );
    }

    function editorPixelHeight() {
        return Math.max(
            420,
            Math.floor(el.editorHost.clientHeight)
        );
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
                    const key = event.key.toLowerCase();

                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 's'
                    ) {
                        event.preventDefault();

                        saveCurrent({
                            quiet: false,
                            automatic: false,
                        }).catch(handleError);
                    }

                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 'n'
                    ) {
                        event.preventDefault();
                        createNote().catch(handleError);
                    }
                });
            },
        });

        state.editor = editors[0]
            || window.tinymce.get('noteEditor');

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

        if (
            localStorage.getItem('browsernote.sidebar')
            === 'collapsed'
        ) {
            el.appShell.classList.add('sidebar-collapsed');
        }

        el.newNoteButton.addEventListener('click', () => {
            createNote().catch(handleError);
        });

        el.saveButton.addEventListener('click', () => {
            saveCurrent({
                quiet: false,
                automatic: false,
            }).catch(handleError);
        });

        el.noteTitle.addEventListener('input', markDirty);
        el.noteFolderSelect.addEventListener('change', markDirty);

        el.noteTitle.addEventListener('keydown', (event) => {
            const key = event.key.toLowerCase();

            if (event.key === 'Enter') {
                event.preventDefault();
                state.editor?.focus();
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === 's'
            ) {
                event.preventDefault();

                saveCurrent({
                    quiet: false,
                    automatic: false,
                }).catch(handleError);
            }
        });

        el.addFolderButton.addEventListener('click', () => {
            createFolder().catch(handleError);
        });

        el.allNotesFolder.addEventListener('click', async () => {
            try {
                if (state.mode !== 'active') {
                    await switchMode('active');
                }

                state.folderFilter = 'all';
                setActiveFolderButton();
                renderNotes();

                const list = currentVisibleNotes();

                if (list.length > 0) {
                    await openNote(Number(list[0].id));
                } else {
                    clearCurrentEditor();
                }
            } catch (error) {
                handleError(error);
            }
        });

        el.unfiledFolder.addEventListener('click', async () => {
            try {
                if (state.mode !== 'active') {
                    await switchMode('active');
                }

                state.folderFilter = 'unfiled';
                setActiveFolderButton();
                renderNotes();

                const list = currentVisibleNotes();

                if (list.length > 0) {
                    await openNote(Number(list[0].id));
                } else {
                    clearCurrentEditor();
                }
            } catch (error) {
                handleError(error);
            }
        });

        el.archiveNavButton.addEventListener('click', () => {
            switchMode('archived').catch(handleError);
        });

        el.trashNavButton.addEventListener('click', () => {
            switchMode('trash').catch(handleError);
        });

        el.archiveAction.addEventListener('click', () => {
            archiveCurrent().catch(handleError);
        });

        el.trashAction.addEventListener('click', () => {
            moveCurrentToTrash().catch(handleError);
        });

        el.restoreAction.addEventListener('click', () => {
            restoreCurrent().catch(handleError);
        });

        el.forceDeleteAction.addEventListener('click', () => {
            forceDeleteCurrent().catch(handleError);
        });

        el.renameFolderAction.addEventListener('click', () => {
            const id = state.folderMenuId;
            closeFolderMenu();

            if (id) {
                renameFolder(id).catch(handleError);
            }
        });

        el.deleteFolderAction.addEventListener('click', () => {
            const id = state.folderMenuId;
            closeFolderMenu();

            if (id) {
                deleteFolder(id).catch(handleError);
            }
        });

        document.addEventListener('click', (event) => {
            if (
                !el.folderMenu.hidden
                && !el.folderMenu.contains(event.target)
            ) {
                closeFolderMenu();
            }
        });

        document.addEventListener('keydown', (event) => {
            const key = event.key.toLowerCase();

            if (event.key === 'Escape') {
                closeFolderMenu();
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === 's'
            ) {
                event.preventDefault();

                saveCurrent({
                    quiet: false,
                    automatic: false,
                }).catch(handleError);
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
            if (state.dirty && !isTrashMode()) {
                clearLocalDraftTimer();
                persistLocalDraftNow();
            }

            if (!state.dirty && !state.saving) {
                return;
            }

            event.preventDefault();
            event.returnValue = '';
        });

        window.addEventListener('pagehide', () => {
            if (state.dirty && !isTrashMode()) {
                clearLocalDraftTimer();
                persistLocalDraftNow();
            }
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

            await Promise.all([
                loadCollections(),
                loadFolders(),
            ]);

            updateModeUI();
            renderFolders();
            renderNotes();

            if (state.collections.active.length > 0) {
                await openNote(
                    Number(state.collections.active[0].id)
                );
            } else {
                clearCurrentEditor();
            }

            if (!state.dirty) {
                setSaveState('Tersimpan', 'saved');
            }
        } catch (error) {
            handleError(error);
        }
    }

    window.BrowserNoteRecovery = {
        getCurrentDraft() {
            return readLocalDraft(state.currentId);
        },

        persistNow() {
            return persistLocalDraftNow();
        },

        clearCurrentDraft() {
            clearLocalDraft(state.currentId);
        },
    };

    window.BrowserNoteFolders = {
        reload() {
            return loadFolders();
        },

        getFolders() {
            return [...state.folders];
        },

        getFilter() {
            return state.folderFilter;
        },
    };

    window.BrowserNoteStatus = {
        getMode() {
            return state.mode;
        },

        getCounts() {
            return {
                active: state.collections.active.length,
                archived: state.collections.archived.length,
                trash: state.collections.trash.length,
            };
        },

        switchMode(mode) {
            return switchMode(mode);
        },
    };

    boot();
})();
'@

Write-Utf8NoBom -Path $JsPath -Content $js
Ok "JavaScript Archive + Trash dipasang"

Step "6. PHP LINT"

$lint = & $PhpExe -l $ViewPath 2>&1

if ($LASTEXITCODE -ne 0) {
    $lint | ForEach-Object { Write-Host $_ }
    Fail "PHP lint view gagal."
}

Ok "View syntax valid"

Step "7. STATIC UI VERIFICATION"

$viewText = [System.IO.File]::ReadAllText($ViewPath)
$jsText = [System.IO.File]::ReadAllText($JsPath)

foreach ($fragment in @(
    'id="archiveNavButton"',
    'id="trashNavButton"',
    'id="archiveAction"',
    'id="restoreAction"',
    'id="forceDeleteAction"'
)) {
    if (-not $viewText.Contains($fragment)) {
        Fail "Elemen Archive/Trash tidak ditemukan: $fragment"
    }

    Ok "Verified UI: $fragment"
}

foreach ($fragment in @(
    "state.mode = 'active'",
    'async function loadCollections()',
    'async function archiveCurrent()',
    'async function moveCurrentToTrash()',
    'async function restoreCurrent()',
    'async function forceDeleteCurrent()',
    "status=archived",
    "status=trash",
    'readonly'
)) {
    if (-not $jsText.Contains($fragment)) {
        Fail "Fitur Stage 08 tidak ditemukan: $fragment"
    }

    Ok "Verified JS: $fragment"
}

Step "8. HTTP SMOKE TEST"

try {
    $page = Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 8
    $jsHttp = Invoke-WebRequest -Uri "$BaseUrl/assets/js/browsernote.js" -UseBasicParsing -TimeoutSec 8
}
catch {
    Fail "Root atau JavaScript tidak dapat diakses."
}

if ($page.StatusCode -ne 200 -or $jsHttp.StatusCode -ne 200) {
    Fail "HTTP smoke test gagal."
}

if ($page.Content -notlike '*id="archiveNavButton"*') {
    Fail "Apache masih menyajikan view lama."
}

if ($jsHttp.Content -notlike '*async function archiveCurrent()*') {
    Fail "Apache masih menyajikan JavaScript lama."
}

Ok "HTTP Stage 08 PASS"

Step "9. ARCHIVE + TRASH API WORKFLOW TEST"

$testId = $null

try {
    $created = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes" -Body @{
        title = '__STAGE08_STATUS_TEST__'
        content = '<p>archive trash workflow</p>'
    }

    $testId = [int]$created.data.id

    $archived = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes/$testId/archive"

    if ([int]$archived.data.is_archived -ne 1) {
        Fail "Archive API workflow gagal."
    }

    $archivedList = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/notes?status=archived"

    if (-not @($archivedList.data | Where-Object { [int]$_.id -eq $testId })) {
        Fail "Catatan test tidak muncul di Arsip."
    }

    $restoredArchive = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes/$testId/restore-archive"

    if ([int]$restoredArchive.data.is_archived -ne 0) {
        Fail "Restore Archive gagal."
    }

    $trashed = Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId"

    if ([int]$trashed.data.is_deleted -ne 1) {
        Fail "Trash API workflow gagal."
    }

    $trashList = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/notes?status=trash"

    if (-not @($trashList.data | Where-Object { [int]$_.id -eq $testId })) {
        Fail "Catatan test tidak muncul di Sampah."
    }

    $restoredTrash = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes/$testId/restore-trash"

    if ([int]$restoredTrash.data.is_deleted -ne 0) {
        Fail "Restore Trash gagal."
    }

    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId" | Out-Null
    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId/force" | Out-Null

    $testId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Workflow API Stage 08 gagal."
}

Ok "Archive API PASS"
Ok "Archive list PASS"
Ok "Restore Archive PASS"
Ok "Trash API PASS"
Ok "Trash list PASS"
Ok "Restore Trash PASS"
Ok "Force Delete PASS"
Ok "Test cleanup PASS"

Step "10. FINAL COUNTS SMOKE TEST"

try {
    $active = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/notes?status=active"
    $archived = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/notes?status=archived"
    $trash = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/notes?status=trash"
}
catch {
    Fail "Final status count test gagal."
}

Ok "Active count: $($active.count)"
Ok "Archive count: $($archived.count)"
Ok "Trash count: $($trash.count)"

Step "STAGE 08 PASS"

Write-Host ""
Write-Host "Project       : $ProjectRoot" -ForegroundColor White
Write-Host "URL           : $BaseUrl/" -ForegroundColor White
Write-Host "Archive UI    : PASS" -ForegroundColor White
Write-Host "Trash UI      : PASS" -ForegroundColor White
Write-Host "Restore       : PASS" -ForegroundColor White
Write-Host "Force delete  : PASS" -ForegroundColor White
Write-Host "Archive edit  : ENABLED" -ForegroundColor White
Write-Host "Trash edit    : READ-ONLY" -ForegroundColor White
Write-Host "Autosave      : retained" -ForegroundColor White
Write-Host "Local recovery: retained" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 08:" -ForegroundColor Green
Write-Host "1. Buka catatan aktif lalu klik Arsipkan." -ForegroundColor White
Write-Host "2. Pastikan catatan pindah ke Arsip dan badge Arsip tampil." -ForegroundColor White
Write-Host "3. Edit catatan di Arsip dan tunggu autosave." -ForegroundColor White
Write-Host "4. Klik Pulihkan dan pastikan kembali ke Semua Catatan." -ForegroundColor White
Write-Host "5. Klik Sampah pada catatan aktif." -ForegroundColor White
Write-Host "6. Pastikan editor Sampah read-only." -ForegroundColor White
Write-Host "7. Klik Pulihkan dan pastikan catatan aktif kembali." -ForegroundColor White
Write-Host "8. Pindahkan lagi ke Sampah lalu uji Hapus Permanen." -ForegroundColor White
Write-Host "9. Pastikan angka Arsip dan Sampah di sidebar ikut berubah." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 09 - Search judul + isi catatan" -ForegroundColor Green
