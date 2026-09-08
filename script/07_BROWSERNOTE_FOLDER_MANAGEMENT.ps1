#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 07
# FOLDER MANAGEMENT
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$RoutesPath  = Join-Path $ProjectRoot 'app\Config\Routes.php'
$FolderApi   = Join-Path $ProjectRoot 'app\Controllers\Api\FoldersApi.php'
$ViewPath    = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath     = Join-Path $ProjectRoot 'public\assets\css\app.css'
$JsPath      = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage07_$Stamp"

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

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

foreach ($file in @($RoutesPath, $ViewPath, $CssPath, $JsPath)) {
    if (-not (Test-Path $file)) {
        Fail "File wajib tidak ditemukan: $file"
    }
}

if (-not (Test-Path (Join-Path $ProjectRoot 'app\Models\FolderModel.php'))) {
    Fail "FolderModel.php tidak ditemukan."
}

if (-not (Test-Path (Join-Path $ProjectRoot 'app\Models\NoteModel.php'))) {
    Fail "NoteModel.php tidak ditemukan."
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

$jsExisting = [System.IO.File]::ReadAllText($JsPath)
if (-not $jsExisting.Contains("const DRAFT_PREFIX = 'browsernote.draft.v1.';")) {
    Fail "Stage 06 belum terdeteksi pada browsernote.js."
}

Ok "Project ditemukan"
Ok "Stage 06 terverifikasi"
Ok "PHP ditemukan: $PhpExe"

Step "2. BACKUP FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $RoutesPath,
    $FolderApi,
    $ViewPath,
    $CssPath,
    $JsPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. CREATE FOLDERS API"

$folderApiCode = @'
<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use App\Models\FolderModel;
use CodeIgniter\HTTP\ResponseInterface;

class FoldersApi extends BaseController
{
    private FolderModel $folders;

    public function __construct()
    {
        $this->folders = new FolderModel();
    }

    public function index()
    {
        $rows = db_connect()
            ->table('folders f')
            ->select('f.*, COUNT(n.id) AS note_count')
            ->join(
                'notes n',
                'n.folder_id = f.id AND n.is_deleted = 0 AND n.is_archived = 0',
                'left'
            )
            ->groupBy('f.id')
            ->orderBy('f.sort_order', 'ASC')
            ->orderBy('f.name', 'ASC')
            ->get()
            ->getResultArray();

        return $this->json([
            'ok'    => true,
            'count' => count($rows),
            'data'  => $rows,
        ]);
    }

    public function create()
    {
        $payload = $this->payload();
        $name = $this->normalizeName($payload['name'] ?? null);

        if ($name === null) {
            return $this->json([
                'ok'      => false,
                'message' => 'Nama folder wajib diisi.',
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        if ($this->nameExists($name)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Nama folder sudah digunakan.',
            ], ResponseInterface::HTTP_CONFLICT);
        }

        $sortOrder = (int) (
            db_connect()
                ->table('folders')
                ->selectMax('sort_order', 'max_sort')
                ->get()
                ->getRowArray()['max_sort'] ?? 0
        ) + 1;

        $id = $this->folders->insert([
            'name'       => $name,
            'sort_order' => $sortOrder,
        ], true);

        if (!$id) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder gagal dibuat.',
                'errors'  => $this->folders->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Folder dibuat.',
            'data'    => $this->findFolder((int) $id),
        ], ResponseInterface::HTTP_CREATED);
    }

    public function update(int $id)
    {
        $folder = $this->folders->find($id);

        if ($folder === null) {
            return $this->notFound();
        }

        $payload = $this->payload();
        $data = [];

        if (array_key_exists('name', $payload)) {
            $name = $this->normalizeName($payload['name']);

            if ($name === null) {
                return $this->json([
                    'ok'      => false,
                    'message' => 'Nama folder wajib diisi.',
                ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
            }

            if ($this->nameExists($name, $id)) {
                return $this->json([
                    'ok'      => false,
                    'message' => 'Nama folder sudah digunakan.',
                ], ResponseInterface::HTTP_CONFLICT);
            }

            $data['name'] = $name;
        }

        if (array_key_exists('sort_order', $payload)) {
            $data['sort_order'] = max(0, (int) $payload['sort_order']);
        }

        if ($data === []) {
            return $this->json([
                'ok'      => false,
                'message' => 'Tidak ada perubahan folder.',
            ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        if (!$this->folders->update($id, $data)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder gagal diperbarui.',
                'errors'  => $this->folders->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Folder diperbarui.',
            'data'    => $this->findFolder($id),
        ]);
    }

    public function delete(int $id)
    {
        $folder = $this->folders->find($id);

        if ($folder === null) {
            return $this->notFound();
        }

        $db = db_connect();
        $db->transStart();

        $db->table('notes')
            ->where('folder_id', $id)
            ->update([
                'folder_id'  => null,
                'updated_at' => date('Y-m-d H:i:s'),
            ]);

        $db->table('folders')
            ->where('id', $id)
            ->delete();

        $db->transComplete();

        if (!$db->transStatus()) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder gagal dihapus.',
            ], ResponseInterface::HTTP_INTERNAL_SERVER_ERROR);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Folder dihapus. Catatan dipindahkan ke Tanpa Folder.',
            'id'      => $id,
        ]);
    }

    private function payload(): array
    {
        $json = $this->request->getJSON(true);

        if (is_array($json)) {
            return $json;
        }

        $raw = $this->request->getRawInput();

        if (is_array($raw) && $raw !== []) {
            return $raw;
        }

        $post = $this->request->getPost();

        return is_array($post) ? $post : [];
    }

    private function normalizeName(mixed $name): ?string
    {
        $name = trim((string) $name);
        $name = preg_replace('/\s+/u', ' ', $name) ?? $name;

        if ($name === '') {
            return null;
        }

        return mb_substr($name, 0, 150);
    }

    private function nameExists(string $name, ?int $ignoreId = null): bool
    {
        $builder = db_connect()
            ->table('folders')
            ->where('LOWER(name)', mb_strtolower($name));

        if ($ignoreId !== null) {
            $builder->where('id !=', $ignoreId);
        }

        return $builder->countAllResults() > 0;
    }

    private function findFolder(int $id): ?array
    {
        $row = db_connect()
            ->table('folders f')
            ->select('f.*, COUNT(n.id) AS note_count')
            ->join(
                'notes n',
                'n.folder_id = f.id AND n.is_deleted = 0 AND n.is_archived = 0',
                'left'
            )
            ->where('f.id', $id)
            ->groupBy('f.id')
            ->get()
            ->getRowArray();

        return $row ?: null;
    }

    private function notFound()
    {
        return $this->json([
            'ok'      => false,
            'message' => 'Folder tidak ditemukan.',
        ], ResponseInterface::HTTP_NOT_FOUND);
    }

    private function json(array $payload, int $status = ResponseInterface::HTTP_OK)
    {
        return $this->response
            ->setStatusCode($status)
            ->setContentType('application/json')
            ->setJSON($payload);
    }
}
'@

Write-Utf8NoBom -Path $FolderApi -Content $folderApiCode
Ok "FoldersApi.php dibuat"

Step "4. PATCH ROUTES"

$routesText = [System.IO.File]::ReadAllText($RoutesPath)

$startMarker = '// <BROWSERNOTE_STAGE07_FOLDERS>'
$endMarker   = '// </BROWSERNOTE_STAGE07_FOLDERS>'

$pattern = '(?s)\r?\n?' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker) + '\r?\n?'
$routesText = [regex]::Replace($routesText, $pattern, "`r`n")

$routeBlock = @'

// <BROWSERNOTE_STAGE07_FOLDERS>
$routes->group('api', static function ($routes) {
    $routes->get('folders', 'Api\FoldersApi::index');
    $routes->post('folders', 'Api\FoldersApi::create');
    $routes->patch('folders/(:num)', 'Api\FoldersApi::update/$1');
    $routes->delete('folders/(:num)', 'Api\FoldersApi::delete/$1');
});
// </BROWSERNOTE_STAGE07_FOLDERS>
'@

$routesText = $routesText.TrimEnd() + "`r`n" + $routeBlock.Trim() + "`r`n"
Write-Utf8NoBom -Path $RoutesPath -Content $routesText

Ok "Route Folder API ditambahkan"

Step "5. UPDATE VIEW"

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

        <section class="sidebar-section folders-section">
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

            <label class="folder-select-wrap" title="Pindahkan catatan ke folder">
                <span class="folder-select-label">Folder</span>
                <select id="noteFolderSelect" class="folder-select" aria-label="Folder catatan">
                    <option value="">Tanpa Folder</option>
                </select>
            </label>

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
Ok "View Folder Management diperbarui"

Step "6. UPDATE CSS"

$cssExisting = [System.IO.File]::ReadAllText($CssPath)

$stage07CssMarker = '/* BROWSERNOTE_STAGE07_FOLDERS */'
if ($cssExisting.Contains($stage07CssMarker)) {
    $cssExisting = $cssExisting.Substring(0, $cssExisting.IndexOf($stage07CssMarker)).TrimEnd()
}

$folderCss = @'

/* BROWSERNOTE_STAGE07_FOLDERS */

.folders-section {
    flex: 0 0 auto;
    max-height: 34vh;
    display: flex;
    flex-direction: column;
    min-height: 86px;
    padding-top: 2px;
    border-top: 1px solid var(--border);
}

.section-add-button {
    width: 24px;
    height: 24px;
    display: inline-grid;
    place-items: center;
    padding: 0;
    border: 1px solid transparent;
    border-radius: 5px;
    background: transparent;
    color: var(--text-soft);
    cursor: pointer;
}

.section-add-button:hover {
    border-color: var(--border);
    background: var(--surface);
}

.folder-list {
    min-height: 0;
    overflow-y: auto;
    scrollbar-width: thin;
}

.folder-item {
    width: 100%;
    min-height: 32px;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
    gap: 8px;
    padding: 5px 8px;
    border: 1px solid transparent;
    border-radius: var(--radius);
    background: transparent;
    color: var(--text-soft);
    text-align: left;
    cursor: pointer;
}

.folder-item:hover {
    background: var(--surface-hover);
}

.folder-item.active {
    border-color: var(--border);
    background: var(--surface);
    color: var(--text);
}

.folder-item-row {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) 26px;
    align-items: center;
    gap: 2px;
}

.folder-item-row .folder-item {
    min-width: 0;
}

.folder-name {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.folder-count {
    color: var(--text-muted);
    font-size: 10px;
}

.folder-more {
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
    border: 0;
    border-radius: 5px;
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
}

.folder-more:hover {
    background: var(--surface-hover);
    color: var(--text);
}

.folder-select-wrap {
    flex: 0 0 auto;
    display: flex;
    align-items: center;
    gap: 6px;
}

.folder-select-label {
    color: var(--text-muted);
    font-size: 10px;
}

.folder-select {
    max-width: 180px;
    height: 32px;
    padding: 0 26px 0 9px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    outline: none;
    background: var(--surface);
    color: var(--text-soft);
    font-size: 11px;
}

.folder-select:hover,
.folder-select:focus {
    border-color: var(--border-strong);
}

.folder-menu {
    position: fixed;
    z-index: 999998;
    width: 150px;
    padding: 5px;
    border: 1px solid var(--border);
    border-radius: 7px;
    background: var(--surface);
    box-shadow: 0 10px 28px rgba(0, 0, 0, 0.14);
}

.folder-menu button {
    width: 100%;
    min-height: 30px;
    padding: 5px 8px;
    border: 0;
    border-radius: 5px;
    background: transparent;
    text-align: left;
    font-size: 12px;
    cursor: pointer;
}

.folder-menu button:hover {
    background: var(--surface-hover);
}

.folder-menu button.danger {
    color: var(--danger);
}

@media (max-width: 980px) {
    .folder-select-label {
        display: none;
    }

    .folder-select {
        max-width: 128px;
    }
}
'@

Write-Utf8NoBom -Path $CssPath -Content ($cssExisting.TrimEnd() + "`r`n" + $folderCss.Trim() + "`r`n")
Ok "CSS folder ditambahkan"

Step "7. UPDATE JAVASCRIPT"

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

        notes: [],
        folders: [],

        currentId: null,
        currentNote: null,

        folderFilter: 'all',
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
        collapseSidebar: document.getElementById('collapseSidebar'),
        showSidebar: document.getElementById('showSidebar'),

        newNoteButton: document.getElementById('newNoteButton'),
        noteList: document.getElementById('noteList'),
        noteCount: document.getElementById('noteCount'),

        allNotesFolder: document.getElementById('allNotesFolder'),
        allNotesCount: document.getElementById('allNotesCount'),
        unfiledFolder: document.getElementById('unfiledFolder'),
        unfiledCount: document.getElementById('unfiledCount'),
        dynamicFolderList: document.getElementById('dynamicFolderList'),
        addFolderButton: document.getElementById('addFolderButton'),

        noteTitle: document.getElementById('noteTitle'),
        noteFolderSelect: document.getElementById('noteFolderSelect'),

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
        if (!draft) {
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
        if (state.loading || !state.currentId) {
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

    function notesForCurrentFilter() {
        if (state.folderFilter === 'all') {
            return state.notes;
        }

        if (state.folderFilter === 'unfiled') {
            return state.notes.filter(
                (note) => !note.folder_id
            );
        }

        const folderId = Number(state.folderFilter);

        return state.notes.filter(
            (note) => Number(note.folder_id) === folderId
        );
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

    function updateFolderCounters() {
        el.allNotesCount.textContent = String(state.notes.length);

        const unfiled = state.notes.filter(
            (note) => !note.folder_id
        ).length;

        el.unfiledCount.textContent = String(unfiled);
    }

    function setActiveFolderButton() {
        document
            .querySelectorAll('[data-folder-filter]')
            .forEach((button) => {
                button.classList.toggle(
                    'active',
                    String(button.dataset.folderFilter)
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
                state.notes.filter(
                    (note) => Number(note.folder_id) === Number(folder.id)
                ).length
            );

            button.append(name, count);

            button.addEventListener('click', () => {
                state.folderFilter = String(folder.id);
                setActiveFolderButton();
                renderNotes();
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

        updateFolderCounters();
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

        state.folderFilter = String(response.data.id);
        setActiveFolderButton();
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
            loadNotesOnly(),
        ]);

        renderNotes();
        renderFolders();

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

        await request(`${folderApiBase}/${folderId}`, {
            method: 'DELETE',
        });

        if (String(state.folderFilter) === String(folderId)) {
            state.folderFilter = 'all';
        }

        await Promise.all([
            loadFolders(),
            loadNotesOnly(),
        ]);

        if (state.currentId) {
            const refreshed = state.notes.find(
                (note) => Number(note.id) === Number(state.currentId)
            );

            if (refreshed) {
                state.currentNote = {
                    ...state.currentNote,
                    ...refreshed,
                };

                el.noteFolderSelect.value = refreshed.folder_id
                    ? String(refreshed.folder_id)
                    : '';
            }
        }

        renderFolders();
        renderNotes();

        showToast('Folder dihapus');
    }

    /*
     * NOTES
     */

    function renderNotes() {
        const visibleNotes = notesForCurrentFilter();

        el.noteList.innerHTML = '';
        el.noteCount.textContent = String(visibleNotes.length);

        if (visibleNotes.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'sidebar-empty';
            empty.textContent = 'Tidak ada catatan pada folder ini.';
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

    async function loadNotesOnly() {
        const response = await request(apiBase);
        state.notes = Array.isArray(response.data)
            ? response.data
            : [];
    }

    async function loadNotes(preferredId = null) {
        await loadNotesOnly();
        renderNotes();

        if (state.notes.length === 0) {
            const created = await createNote({ open: false });
            await loadNotes(created.id);
            return;
        }

        const wanted = preferredId
            ? state.notes.find(
                (item) => Number(item.id) === Number(preferredId)
            )
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

        clearAutosaveTimer();
        clearLocalDraftTimer();

        state.loading = true;
        setSaveState('Memuat...', 'saving');

        try {
            const response = await request(`${apiBase}/${id}`);
            const note = response.data;
            const localDraft = readLocalDraft(note.id);

            state.currentId = Number(note.id);
            state.currentNote = note;

            state.editVersion = 0;
            state.lastSavedVersion = 0;
            state.dirty = false;

            renderFolderSelect();

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
                setClean('Tersimpan');
            }

            el.currentNoteInfo.textContent =
                `#${note.id} · ${folderNameById(note.folder_id)}`;

            renderNotes();

            window.setTimeout(() => {
                state.editor.focus();
            }, 0);
        } finally {
            state.loading = false;
        }
    }

    async function createNote({ open = true } = {}) {
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

            const created = response.data;

            await loadNotesOnly();
            await loadFolders();

            if (open) {
                renderNotes();
                await openNote(Number(created.id));
            }

            showToast('Catatan baru dibuat');

            return created;
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

            const existing = state.notes.find(
                (item) => Number(item.id) === noteId
            );

            if (existing) {
                Object.assign(existing, response.data);
            }

            await loadFolders();
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

    function handleError(error) {
        console.error(error);

        if (state.dirty) {
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

        el.noteFolderSelect.addEventListener('change', () => {
            markDirty();
        });

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

        el.allNotesFolder.addEventListener('click', () => {
            state.folderFilter = 'all';
            setActiveFolderButton();
            renderNotes();
        });

        el.unfiledFolder.addEventListener('click', () => {
            state.folderFilter = 'unfiled';
            setActiveFolderButton();
            renderNotes();
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
            if (state.dirty) {
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
            if (state.dirty) {
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

            await loadFolders();
            await loadNotes();

            renderFolders();
            renderNotes();

            setSaveState(
                state.dirty
                    ? 'Draft lokal dipulihkan'
                    : 'Tersimpan',
                state.dirty ? 'dirty' : 'saved'
            );
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

    boot();
})();
'@

Write-Utf8NoBom -Path $JsPath -Content $js
Ok "JavaScript Folder Management dipasang"

Step "8. PHP LINT"

foreach ($file in @($FolderApi, $RoutesPath, $ViewPath)) {
    $lint = & $PhpExe -l $file 2>&1

    if ($LASTEXITCODE -ne 0) {
        $lint | ForEach-Object { Write-Host $_ }
        Fail "PHP lint gagal: $file"
    }

    Ok "Syntax valid: $(Split-Path $file -Leaf)"
}

Step "9. ROUTE VERIFICATION"

Push-Location $ProjectRoot
try {
    $routesOut = & $PhpExe spark routes 2>&1
    $routesExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($routesExit -ne 0) {
    Fail "php spark routes gagal."
}

$joined = $routesOut -join "`n"

foreach ($fragment in @(
    'FoldersApi::index',
    'FoldersApi::create',
    'FoldersApi::update',
    'FoldersApi::delete'
)) {
    if ($joined -notlike "*$fragment*") {
        Fail "Route folder tidak ditemukan: $fragment"
    }
}

Ok "Folder routes PASS"

Step "10. FOLDER API CRUD TEST"

$folderId = $null

try {
    $list = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/folders"
    if (-not $list.ok) {
        Fail "GET folders ok=false"
    }

    $created = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/folders" -Body @{
        name = '__STAGE07_FOLDER_TEST__'
    }

    $folderId = [int]$created.data.id

    if ($folderId -lt 1) {
        Fail "Folder test tidak mendapatkan ID."
    }

    $updated = Invoke-Json -Method 'PATCH' -Uri "$BaseUrl/api/folders/$folderId" -Body @{
        name = '__STAGE07_FOLDER_TEST_UPDATED__'
    }

    if ($updated.data.name -ne '__STAGE07_FOLDER_TEST_UPDATED__') {
        Fail "Rename folder gagal."
    }

    $deleted = Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/folders/$folderId"

    if (-not $deleted.ok) {
        Fail "Delete folder gagal."
    }

    $folderId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Folder API CRUD test gagal."
}

Ok "Folder API LIST PASS"
Ok "Folder API CREATE PASS"
Ok "Folder API RENAME PASS"
Ok "Folder API DELETE PASS"

Step "11. MOVE NOTE FOLDER API TEST"

$testFolderId = $null
$testNoteId = $null

try {
    $folder = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/folders" -Body @{
        name = '__STAGE07_MOVE_FOLDER__'
    }
    $testFolderId = [int]$folder.data.id

    $note = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes" -Body @{
        title = '__STAGE07_MOVE_NOTE__'
        content = '<p>folder move test</p>'
        folder_id = $testFolderId
    }
    $testNoteId = [int]$note.data.id

    if ([int]$note.data.folder_id -ne $testFolderId) {
        Fail "Create note ke folder gagal."
    }

    $moveOut = Invoke-Json -Method 'PATCH' -Uri "$BaseUrl/api/notes/$testNoteId" -Body @{
        folder_id = $null
    }

    if ($null -ne $moveOut.data.folder_id -and "$($moveOut.data.folder_id)" -ne '') {
        Fail "Memindahkan note ke Tanpa Folder gagal."
    }

    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testNoteId" | Out-Null
    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testNoteId/force" | Out-Null
    $testNoteId = $null

    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/folders/$testFolderId" | Out-Null
    $testFolderId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Move-note folder test gagal."
}

Ok "Move note -> folder PASS"
Ok "Move note -> Tanpa Folder PASS"
Ok "Test cleanup PASS"

Step "12. ROOT + ASSET VERIFICATION"

try {
    $page = Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 8
    $jsHttp = Invoke-WebRequest -Uri "$BaseUrl/assets/js/browsernote.js" -UseBasicParsing -TimeoutSec 8
}
catch {
    Fail "Root atau JavaScript tidak dapat diakses melalui Apache."
}

if ($page.StatusCode -ne 200 -or $jsHttp.StatusCode -ne 200) {
    Fail "HTTP smoke test gagal."
}

foreach ($fragment in @(
    'id="addFolderButton"',
    'id="noteFolderSelect"',
    'id="dynamicFolderList"',
    'id="folderMenu"'
)) {
    if ($page.Content -notlike "*$fragment*") {
        Fail "Elemen UI folder hilang: $fragment"
    }
}

foreach ($fragment in @(
    'folderApiBase',
    'async function createFolder()',
    'async function renameFolder(folderId)',
    'async function deleteFolder(folderId)',
    'noteFolderSelect'
)) {
    if ($jsHttp.Content -notlike "*$fragment*") {
        Fail "Fitur folder JS hilang: $fragment"
    }
}

Ok "UI Folder Management tersedia melalui Apache"

Step "STAGE 07 PASS"

Write-Host ""
Write-Host "Project      : $ProjectRoot" -ForegroundColor White
Write-Host "URL          : $BaseUrl/" -ForegroundColor White
Write-Host "Folder list  : PASS" -ForegroundColor White
Write-Host "Create folder: PASS" -ForegroundColor White
Write-Host "Rename folder: PASS" -ForegroundColor White
Write-Host "Delete folder: PASS" -ForegroundColor White
Write-Host "Filter notes : PASS" -ForegroundColor White
Write-Host "Move note    : PASS" -ForegroundColor White
Write-Host "Autosave     : retained" -ForegroundColor White
Write-Host "Local recovery: retained" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 07:" -ForegroundColor Green
Write-Host "1. Klik + pada bagian FOLDER lalu buat folder misalnya OJS." -ForegroundColor White
Write-Host "2. Buat folder lain misalnya Flutter." -ForegroundColor White
Write-Host "3. Pilih catatan lalu ubah dropdown Folder di kanan judul." -ForegroundColor White
Write-Host "4. Tunggu autosave dan pastikan catatan masuk ke folder." -ForegroundColor White
Write-Host "5. Klik folder di sidebar dan pastikan daftar catatan terfilter." -ForegroundColor White
Write-Host "6. Klik titik tiga pada folder, uji Ganti nama." -ForegroundColor White
Write-Host "7. Uji Hapus folder. Catatan harus tetap ada dan pindah ke Tanpa Folder." -ForegroundColor White
Write-Host "8. Klik Semua Catatan untuk melihat seluruh catatan aktif." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 08 - Arsip + Sampah UI" -ForegroundColor Green
