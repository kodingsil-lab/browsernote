#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 09
# SEARCH TITLE + CONTENT
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$RoutesPath  = Join-Path $ProjectRoot 'app\Config\Routes.php'
$SearchApi   = Join-Path $ProjectRoot 'app\Controllers\Api\SearchApi.php'
$ViewPath    = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath     = Join-Path $ProjectRoot 'public\assets\css\app.css'
$JsPath      = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage09_$Stamp"

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

function Replace-Required {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (-not $Text.Contains($Old)) {
        Fail "Patch marker tidak ditemukan: $Label"
    }

    return $Text.Replace($Old, $New)
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

foreach ($path in @($ProjectRoot, $RoutesPath, $ViewPath, $CssPath, $JsPath)) {
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
    'async function archiveCurrent()',
    'async function moveCurrentToTrash()',
    'async function restoreCurrent()',
    'window.BrowserNoteStatus = {'
)) {
    if (-not $jsExisting.Contains($marker)) {
        Fail "Stage 08 belum lengkap. Marker hilang: $marker"
    }
}

Ok "Project ditemukan"
Ok "Stage 08 terverifikasi"
Ok "PHP ditemukan: $PhpExe"

Step "2. BACKUP CURRENT FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $RoutesPath,
    $SearchApi,
    $ViewPath,
    $CssPath,
    $JsPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. CREATE SEARCH API"

$searchApiCode = @'
<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use CodeIgniter\HTTP\ResponseInterface;

class SearchApi extends BaseController
{
    public function index()
    {
        $query = trim((string) $this->request->getGet('q'));
        $status = strtolower(trim((string) $this->request->getGet('status')));
        $status = $status !== '' ? $status : 'all';

        $limit = (int) $this->request->getGet('limit');
        $limit = $limit > 0 ? min($limit, 100) : 50;

        if (mb_strlen($query) < 1) {
            return $this->json([
                'ok'    => true,
                'query' => $query,
                'count' => 0,
                'data'  => [],
            ]);
        }

        if (!in_array($status, ['all', 'active', 'archived'], true)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Status pencarian tidak valid.',
            ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        $db = db_connect();

        $builder = $db
            ->table('notes n')
            ->select(
                'n.id, n.folder_id, n.title, n.content_text, ' .
                'n.is_archived, n.is_deleted, n.created_at, n.updated_at, ' .
                'f.name AS folder_name'
            )
            ->join('folders f', 'f.id = n.folder_id', 'left')
            ->where('n.is_deleted', 0);

        if ($status === 'active') {
            $builder->where('n.is_archived', 0);
        } elseif ($status === 'archived') {
            $builder->where('n.is_archived', 1);
        }

        $builder
            ->groupStart()
                ->like('n.title', $query, 'both', null, true)
                ->orLike('n.content_text', $query, 'both', null, true)
            ->groupEnd()
            ->orderBy(
                "CASE
                    WHEN LOWER(n.title) = " . $db->escape(mb_strtolower($query)) . " THEN 0
                    WHEN LOWER(n.title) LIKE " . $db->escape('%' . mb_strtolower($query) . '%') . " THEN 1
                    ELSE 2
                END",
                '',
                false
            )
            ->orderBy('n.updated_at', 'DESC')
            ->orderBy('n.id', 'DESC')
            ->limit($limit);

        $rows = $builder->get()->getResultArray();

        foreach ($rows as &$row) {
            $row['snippet'] = $this->makeSnippet(
                (string) ($row['content_text'] ?? ''),
                $query
            );

            unset($row['content_text']);
        }
        unset($row);

        return $this->json([
            'ok'     => true,
            'query'  => $query,
            'status' => $status,
            'count'  => count($rows),
            'data'   => $rows,
        ]);
    }

    private function makeSnippet(string $text, string $query): string
    {
        $text = trim(preg_replace('/\s+/u', ' ', $text) ?? $text);

        if ($text === '') {
            return '';
        }

        $position = mb_stripos($text, $query);

        if ($position === false) {
            return mb_strlen($text) > 120
                ? mb_substr($text, 0, 120) . '…'
                : $text;
        }

        $start = max(0, $position - 45);
        $length = 130;

        $snippet = mb_substr($text, $start, $length);

        if ($start > 0) {
            $snippet = '…' . $snippet;
        }

        if (($start + $length) < mb_strlen($text)) {
            $snippet .= '…';
        }

        return $snippet;
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

Write-Utf8NoBom -Path $SearchApi -Content $searchApiCode
Ok "SearchApi.php dibuat"

Step "4. PATCH ROUTES"

$routesText = [System.IO.File]::ReadAllText($RoutesPath)

$startMarker = '// <BROWSERNOTE_STAGE09_SEARCH>'
$endMarker   = '// </BROWSERNOTE_STAGE09_SEARCH>'

$pattern = '(?s)\r?\n?' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker) + '\r?\n?'
$routesText = [regex]::Replace($routesText, $pattern, "`r`n")

$routeBlock = @'

// <BROWSERNOTE_STAGE09_SEARCH>
$routes->get('api/search', 'Api\SearchApi::index');
// </BROWSERNOTE_STAGE09_SEARCH>
'@

$routesText = $routesText.TrimEnd() + "`r`n" + $routeBlock.Trim() + "`r`n"
Write-Utf8NoBom -Path $RoutesPath -Content $routesText

Ok "Route Search API ditambahkan"

Step "5. ENABLE SEARCH UI"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

$oldSearch = @'
        <label class="search-box is-disabled" title="Pencarian akan diaktifkan pada Stage 09">
            <span class="search-icon">⌕</span>
            <input
                type="search"
                placeholder="Cari catatan..."
                aria-label="Cari catatan"
                disabled
            >
        </label>
'@

$newSearch = @'
        <label class="search-box" id="searchBox" title="Cari judul dan isi catatan">
            <span class="search-icon">⌕</span>
            <input
                id="searchInput"
                type="search"
                placeholder="Cari judul atau isi..."
                aria-label="Cari judul atau isi catatan"
                autocomplete="off"
                spellcheck="false"
            >
            <button
                class="search-clear"
                id="searchClearButton"
                type="button"
                title="Bersihkan pencarian"
                aria-label="Bersihkan pencarian"
                hidden
            >×</button>
        </label>
'@

$viewText = Replace-Required `
    -Text $viewText `
    -Old $oldSearch `
    -New $newSearch `
    -Label 'search box Stage 08'

Write-Utf8NoBom -Path $ViewPath -Content $viewText
Ok "Search UI diaktifkan"

Step "6. APPEND SEARCH CSS"

$cssExisting = [System.IO.File]::ReadAllText($CssPath)
$cssMarker = '/* BROWSERNOTE_STAGE09_SEARCH */'

if ($cssExisting.Contains($cssMarker)) {
    $cssExisting = $cssExisting.Substring(
        0,
        $cssExisting.IndexOf($cssMarker)
    ).TrimEnd()
}

$searchCss = @'

/* BROWSERNOTE_STAGE09_SEARCH */

.search-box:focus-within {
    border-color: var(--border-strong);
    box-shadow: 0 0 0 2px rgba(32, 36, 42, 0.06);
}

.search-clear {
    width: 22px;
    height: 22px;
    flex: 0 0 22px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 5px;
    background: transparent;
    color: var(--text-muted);
    font-size: 15px;
    line-height: 1;
    cursor: pointer;
}

.search-clear:hover {
    background: var(--surface-hover);
    color: var(--text);
}

.note-item.search-result .note-item-meta {
    white-space: normal;
    line-height: 1.35;
}

.search-result-snippet {
    margin-top: 4px;
    display: -webkit-box;
    overflow: hidden;
    color: var(--text-muted);
    font-size: 10px;
    line-height: 1.35;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
}
'@

$combinedCss = $cssExisting.TrimEnd() + "`r`n" + $searchCss.Trim() + "`r`n"
Write-Utf8NoBom -Path $CssPath -Content $combinedCss

Ok "CSS search ditambahkan"

Step "7. PATCH JAVASCRIPT"

$jsText = [System.IO.File]::ReadAllText($JsPath)

$jsText = Replace-Required `
    -Text $jsText `
    -Old "    const folderApiBase = `${config.baseUrl}/api/folders`;" `
    -New "    const folderApiBase = `${config.baseUrl}/api/folders`;`r`n    const searchApiBase = `${config.baseUrl}/api/search`;" `
    -Label 'searchApiBase'

$jsText = Replace-Required `
    -Text $jsText `
    -Old "        folderMenuId: null,`r`n`r`n        dirty: false," `
    -New "        folderMenuId: null,`r`n`r`n        searchQuery: '',`r`n        searchResults: [],`r`n        searchTimer: null,`r`n        searchRequestSeq: 0,`r`n`r`n        dirty: false," `
    -Label 'search state'

$jsText = Replace-Required `
    -Text $jsText `
    -Old "        newNoteButton: document.getElementById('newNoteButton'),`r`n        noteListHeading: document.getElementById('noteListHeading')," `
    -New "        newNoteButton: document.getElementById('newNoteButton'),`r`n        searchBox: document.getElementById('searchBox'),`r`n        searchInput: document.getElementById('searchInput'),`r`n        searchClearButton: document.getElementById('searchClearButton'),`r`n        noteListHeading: document.getElementById('noteListHeading')," `
    -Label 'search elements'

$searchFunctions = @'
    /*
     * SEARCH
     */

    function clearSearchTimer() {
        if (state.searchTimer !== null) {
            window.clearTimeout(state.searchTimer);
            state.searchTimer = null;
        }
    }

    function hasSearch() {
        return state.searchQuery.trim() !== '';
    }

    function focusSearch() {
        el.searchInput.focus();
        el.searchInput.select();
    }

    function clearSearch({ keepFocus = false } = {}) {
        clearSearchTimer();
        state.searchRequestSeq += 1;
        state.searchQuery = '';
        state.searchResults = [];

        el.searchInput.value = '';
        el.searchClearButton.hidden = true;

        updateModeUI();
        renderNotes();

        if (keepFocus) {
            el.searchInput.focus();
        }
    }

    function scheduleSearch() {
        clearSearchTimer();

        const query = el.searchInput.value.trim();

        state.searchQuery = query;
        el.searchClearButton.hidden = query === '';

        if (query === '') {
            state.searchResults = [];
            updateModeUI();
            renderNotes();
            return;
        }

        updateModeUI();
        el.noteList.innerHTML =
            '<div class="sidebar-empty">Mencari...</div>';
        el.noteCount.textContent = '…';

        state.searchTimer = window.setTimeout(() => {
            state.searchTimer = null;
            performSearch(query).catch(handleError);
        }, 240);
    }

    async function performSearch(query = state.searchQuery) {
        const clean = String(query || '').trim();

        if (clean === '') {
            clearSearch();
            return;
        }

        const requestSeq = ++state.searchRequestSeq;

        const response = await request(
            `${searchApiBase}?q=${encodeURIComponent(clean)}&status=all&limit=100`
        );

        if (
            requestSeq !== state.searchRequestSeq
            || clean !== state.searchQuery
        ) {
            return;
        }

        state.searchResults = Array.isArray(response.data)
            ? response.data
            : [];

        updateModeUI();
        renderNotes();
    }

    function searchTargetMode(note) {
        return Number(note.is_archived) === 1
            ? 'archived'
            : 'active';
    }

    async function openSearchResult(note) {
        await flushPendingSave();

        state.mode = searchTargetMode(note);
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(Number(note.id));
    }

'@

$collectionsMarker = "    /*`r`n     * COLLECTIONS + MODE`r`n     */"

if (-not $jsText.Contains($collectionsMarker)) {
    Fail "Marker COLLECTIONS + MODE tidak ditemukan."
}

$jsText = $jsText.Replace(
    $collectionsMarker,
    $searchFunctions.Replace("`n", "`r`n") + $collectionsMarker
)

$oldHeading = @'
        el.noteListHeading.textContent = active
            ? 'CATATAN'
            : archived
                ? 'ARSIP'
                : 'SAMPAH';
'@

$newHeading = @'
        el.noteListHeading.textContent = hasSearch()
            ? 'HASIL PENCARIAN'
            : active
                ? 'CATATAN'
                : archived
                    ? 'ARSIP'
                    : 'SAMPAH';
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $oldHeading.Replace("`n","`r`n") `
    -New $newHeading.Replace("`n","`r`n") `
    -Label 'search heading'

$oldVisible = @'
    function currentVisibleNotes() {
        const collection = currentCollection();

        if (state.mode !== 'active') {
            return collection;
        }
'@

$newVisible = @'
    function currentVisibleNotes() {
        if (hasSearch()) {
            return state.searchResults;
        }

        const collection = currentCollection();

        if (state.mode !== 'active') {
            return collection;
        }
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $oldVisible.Replace("`n","`r`n") `
    -New $newVisible.Replace("`n","`r`n") `
    -Label 'search visible notes'

$oldEmpty = @'
            empty.textContent = state.mode === 'active'
                ? 'Tidak ada catatan pada bagian ini.'
                : state.mode === 'archived'
                    ? 'Belum ada catatan di Arsip.'
                    : 'Sampah kosong.';
'@

$newEmpty = @'
            empty.textContent = hasSearch()
                ? `Tidak ditemukan catatan untuk "${state.searchQuery}".`
                : state.mode === 'active'
                    ? 'Tidak ada catatan pada bagian ini.'
                    : state.mode === 'archived'
                        ? 'Belum ada catatan di Arsip.'
                        : 'Sampah kosong.';
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $oldEmpty.Replace("`n","`r`n") `
    -New $newEmpty.Replace("`n","`r`n") `
    -Label 'search empty state'

$jsText = Replace-Required `
    -Text $jsText `
    -Old "            button.className = 'note-item';`r`n`r`n            if (Number(note.id) === Number(state.currentId)) {" `
    -New "            button.className = hasSearch() ? 'note-item search-result' : 'note-item';`r`n`r`n            if (Number(note.id) === Number(state.currentId)) {" `
    -Label 'search result class'

$oldMeta = @'
            const folder = note.folder_name
                ? `${note.folder_name} · `
                : '';

            meta.textContent = `${folder}${formatDate(note.updated_at)}`;

            button.append(title, meta);
'@

$newMeta = @'
            const folder = note.folder_name
                ? `${note.folder_name} · `
                : '';

            if (hasSearch()) {
                const status = Number(note.is_archived) === 1
                    ? 'Arsip · '
                    : 'Aktif · ';

                meta.textContent =
                    `${status}${folder}${formatDate(note.updated_at)}`;
            } else {
                meta.textContent =
                    `${folder}${formatDate(note.updated_at)}`;
            }

            button.append(title, meta);

            if (hasSearch() && note.snippet) {
                const snippet = document.createElement('div');
                snippet.className = 'search-result-snippet';
                snippet.textContent = note.snippet;
                button.appendChild(snippet);
            }
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $oldMeta.Replace("`n","`r`n") `
    -New $newMeta.Replace("`n","`r`n") `
    -Label 'search metadata'

$oldClick = @'
                try {
                    await flushPendingSave();
                    await openNote(id);
                } catch (error) {
                    handleError(error);
                }
'@

$newClick = @'
                try {
                    if (hasSearch()) {
                        await openSearchResult(note);
                    } else {
                        await flushPendingSave();
                        await openNote(id);
                    }
                } catch (error) {
                    handleError(error);
                }
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $oldClick.Replace("`n","`r`n") `
    -New $newClick.Replace("`n","`r`n") `
    -Label 'search result click'

$bindMarker = @'
        el.newNoteButton.addEventListener('click', () => {
            createNote().catch(handleError);
        });
'@

$bindSearch = @'
        el.searchInput.addEventListener('input', () => {
            scheduleSearch();
        });

        el.searchInput.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                event.preventDefault();
                clearSearch({ keepFocus: true });
            }

            if (
                event.key === 'Enter'
                && state.searchResults.length > 0
            ) {
                event.preventDefault();

                openSearchResult(
                    state.searchResults[0]
                ).catch(handleError);
            }
        });

        el.searchClearButton.addEventListener('click', () => {
            clearSearch({ keepFocus: true });
        });

        el.newNoteButton.addEventListener('click', () => {
            createNote().catch(handleError);
        });
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $bindMarker.Replace("`n","`r`n") `
    -New $bindSearch.Replace("`n","`r`n") `
    -Label 'search bindings'

$editorKeyMarker = @'
                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 's'
                    ) {
'@

$editorKeyReplacement = @'
                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 'f'
                    ) {
                        event.preventDefault();
                        focusSearch();
                        return;
                    }

                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 's'
                    ) {
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $editorKeyMarker.Replace("`n","`r`n") `
    -New $editorKeyReplacement.Replace("`n","`r`n") `
    -Label 'editor Ctrl+F'

$docKeyMarker = @'
            if (event.key === 'Escape') {
                closeFolderMenu();
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === 's'
            ) {
'@

$docKeyReplacement = @'
            if (event.key === 'Escape') {
                closeFolderMenu();

                if (hasSearch()) {
                    clearSearch();
                }
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === 'f'
            ) {
                event.preventDefault();
                focusSearch();
                return;
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === 's'
            ) {
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $docKeyMarker.Replace("`n","`r`n") `
    -New $docKeyReplacement.Replace("`n","`r`n") `
    -Label 'document Ctrl+F'

$bootMarker = "    boot();`r`n})();"

$searchExpose = @'
    window.BrowserNoteSearch = {
        focus() {
            focusSearch();
        },

        clear() {
            clearSearch();
        },

        run(query) {
            el.searchInput.value = String(query || '');
            state.searchQuery = el.searchInput.value.trim();
            el.searchClearButton.hidden = state.searchQuery === '';

            return performSearch(state.searchQuery);
        },

        getQuery() {
            return state.searchQuery;
        },

        getResults() {
            return [...state.searchResults];
        },
    };

    boot();
})();
'@

$jsText = Replace-Required `
    -Text $jsText `
    -Old $bootMarker `
    -New $searchExpose.Replace("`n","`r`n") `
    -Label 'BrowserNoteSearch expose'

Write-Utf8NoBom -Path $JsPath -Content $jsText
Ok "JavaScript Search dipasang"

Step "8. PHP LINT"

foreach ($file in @($SearchApi, $RoutesPath, $ViewPath)) {
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

if ($joined -notlike '*SearchApi::index*') {
    Fail "Route SearchApi::index tidak terdaftar."
}

Ok "Search route PASS"

Step "10. SEARCH API WORKFLOW TEST"

$testId = $null
$token = "Stage09Needle$([Guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    $created = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes" -Body @{
        title = '__STAGE09_SEARCH_TEST__'
        content = "<p>BrowserNote content search $token konfigurasi SMTP 587.</p>"
    }

    $testId = [int]$created.data.id

    $titleSearch = Invoke-Json `
        -Method 'GET' `
        -Uri "${BaseUrl}/api/search?q=$([uri]::EscapeDataString('__STAGE09_SEARCH_TEST__'))&status=all"

    if (-not @($titleSearch.data | Where-Object { [int]$_.id -eq $testId })) {
        Fail "Search berdasarkan judul gagal."
    }

    $contentSearch = Invoke-Json `
        -Method 'GET' `
        -Uri "${BaseUrl}/api/search?q=$([uri]::EscapeDataString($token))&status=all"

    $contentHit = @($contentSearch.data | Where-Object { [int]$_.id -eq $testId })

    if ($contentHit.Count -lt 1) {
        Fail "Search berdasarkan isi gagal."
    }

    if (-not $contentHit[0].snippet) {
        Fail "Snippet hasil search tidak tersedia."
    }

    Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/notes/$testId/archive" | Out-Null

    $archiveSearch = Invoke-Json `
        -Method 'GET' `
        -Uri "${BaseUrl}/api/search?q=$([uri]::EscapeDataString($token))&status=all"

    $archiveHit = @($archiveSearch.data | Where-Object { [int]$_.id -eq $testId })

    if ($archiveHit.Count -lt 1 -or [int]$archiveHit[0].is_archived -ne 1) {
        Fail "Catatan arsip tidak ditemukan dalam pencarian global."
    }

    Invoke-Json `
        -Method 'POST' `
        -Uri "$BaseUrl/api/notes/$testId/restore-archive" | Out-Null

    Invoke-Json `
        -Method 'DELETE' `
        -Uri "$BaseUrl/api/notes/$testId" | Out-Null

    $trashExcluded = Invoke-Json `
        -Method 'GET' `
        -Uri "${BaseUrl}/api/search?q=$([uri]::EscapeDataString($token))&status=all"

    if (@($trashExcluded.data | Where-Object { [int]$_.id -eq $testId }).Count -gt 0) {
        Fail "Catatan Sampah masih muncul pada pencarian."
    }

    Invoke-Json `
        -Method 'DELETE' `
        -Uri "$BaseUrl/api/notes/$testId/force" | Out-Null

    $testId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Search API workflow test gagal."
}

Ok "Search title PASS"
Ok "Search content PASS"
Ok "Search snippet PASS"
Ok "Search archived PASS"
Ok "Trash excluded PASS"
Ok "Test cleanup PASS"

Step "11. HTTP UI VERIFICATION"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8

    $jsHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/browsernote.js" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Root atau JavaScript tidak dapat diakses melalui Apache."
}

if ($page.StatusCode -ne 200 -or $jsHttp.StatusCode -ne 200) {
    Fail "HTTP smoke test gagal."
}

foreach ($fragment in @(
    'id="searchInput"',
    'id="searchClearButton"'
)) {
    if ($page.Content -notlike "*$fragment*") {
        Fail "Search UI tidak tersedia: $fragment"
    }
}

foreach ($fragment in @(
    'searchApiBase',
    'function scheduleSearch()',
    'async function performSearch',
    'window.BrowserNoteSearch',
    "key === 'f'"
)) {
    if ($jsHttp.Content -notlike "*$fragment*") {
        Fail "Search JavaScript tidak tersedia: $fragment"
    }
}

Ok "Search UI tersedia melalui Apache"

Step "STAGE 09 PASS"

Write-Host ""
Write-Host "Project       : $ProjectRoot" -ForegroundColor White
Write-Host "URL           : $BaseUrl/" -ForegroundColor White
Write-Host "Title search  : PASS" -ForegroundColor White
Write-Host "Content search: PASS" -ForegroundColor White
Write-Host "Snippet       : PASS" -ForegroundColor White
Write-Host "Active notes  : searchable" -ForegroundColor White
Write-Host "Archived notes: searchable" -ForegroundColor White
Write-Host "Trash         : excluded" -ForegroundColor White
Write-Host "Debounce      : 240 ms" -ForegroundColor White
Write-Host "Ctrl + F      : app search" -ForegroundColor White
Write-Host "Esc           : clear search" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 09:" -ForegroundColor Green
Write-Host "1. Ketik kata yang ada pada JUDUL catatan." -ForegroundColor White
Write-Host "2. Ketik kata yang hanya ada di ISI catatan." -ForegroundColor White
Write-Host "3. Pastikan snippet isi muncul pada hasil." -ForegroundColor White
Write-Host "4. Arsipkan satu catatan lalu cari kata di dalamnya." -ForegroundColor White
Write-Host "5. Klik hasil Arsip dan pastikan mode berpindah ke Arsip." -ForegroundColor White
Write-Host "6. Tekan Ctrl+F dan pastikan fokus masuk ke kolom pencarian." -ForegroundColor White
Write-Host "7. Tekan Esc untuk membersihkan pencarian." -ForegroundColor White
Write-Host "8. Pastikan catatan di Sampah tidak muncul di hasil." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 10 - Quick Note + keyboard shortcuts final" -ForegroundColor Green
