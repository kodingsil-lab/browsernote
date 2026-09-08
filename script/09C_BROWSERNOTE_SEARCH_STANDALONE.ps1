#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 09C
# SEARCH STANDALONE - ROBUST / IDEMPOTENT
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$RoutesPath  = Join-Path $ProjectRoot 'app\Config\Routes.php'
$SearchApi   = Join-Path $ProjectRoot 'app\Controllers\Api\SearchApi.php'
$ViewPath    = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath     = Join-Path $ProjectRoot 'public\assets\css\app.css'
$MainJsPath  = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$SearchJsPath = Join-Path $ProjectRoot 'public\assets\js\search.js'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage09c_$Stamp"

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

foreach ($path in @($ProjectRoot, $RoutesPath, $ViewPath, $CssPath, $MainJsPath)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)

foreach ($marker in @(
    'async function archiveCurrent()',
    'async function restoreCurrent()',
    'window.BrowserNoteStatus = {'
)) {
    if (-not $mainJs.Contains($marker)) {
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
    $MainJsPath,
    $SearchJsPath
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

        if ($query === '') {
            return $this->json([
                'ok'    => true,
                'query' => '',
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

        $builder = db_connect()
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
                ->like('n.title', $query)
                ->orLike('n.content_text', $query)
            ->groupEnd()
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
Ok "SearchApi.php ditulis"

Step "4. PATCH SEARCH ROUTE IDEMPOTENT"

$routesText = [System.IO.File]::ReadAllText($RoutesPath)

$routeStart = '// <BROWSERNOTE_STAGE09_SEARCH>'
$routeEnd   = '// </BROWSERNOTE_STAGE09_SEARCH>'

$routePattern = '(?s)\r?\n?' + [regex]::Escape($routeStart) + '.*?' + [regex]::Escape($routeEnd) + '\r?\n?'
$routesText = [regex]::Replace($routesText, $routePattern, "`r`n")

$routeBlock = @'

// <BROWSERNOTE_STAGE09_SEARCH>
$routes->get('api/search', 'Api\SearchApi::index');
// </BROWSERNOTE_STAGE09_SEARCH>
'@

$routesText = $routesText.TrimEnd() + "`r`n" + $routeBlock.Trim() + "`r`n"
Write-Utf8NoBom -Path $RoutesPath -Content $routesText

Ok "Search route dipasang"

Step "5. ENABLE SEARCH BOX ROBUSTLY"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

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

if (-not $viewText.Contains('id="searchInput"')) {
    $searchPattern = '(?s)<label\s+class="search-box[^"]*"[^>]*>.*?</label>'
    $match = [regex]::Match($viewText, $searchPattern)

    if (-not $match.Success) {
        Fail "Elemen .search-box tidak ditemukan pada view."
    }

    $viewText = [regex]::Replace(
        $viewText,
        $searchPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $newSearch
        },
        1
    )
}

$searchScriptTag = '<script src="<?= base_url(''assets/js/search.js'') ?>"></script>'

if (-not $viewText.Contains('assets/js/search.js')) {
    $browserNoteTag = '<script src="<?= base_url(''assets/js/browsernote.js'') ?>"></script>'

    if (-not $viewText.Contains($browserNoteTag)) {
        Fail "Tag browsernote.js tidak ditemukan pada view."
    }

    $viewText = $viewText.Replace(
        $browserNoteTag,
        $browserNoteTag + "`r`n" + $searchScriptTag
    )
}

Write-Utf8NoBom -Path $ViewPath -Content $viewText

Ok "Search box aktif"
Ok "search.js ditambahkan ke view"

Step "6. ADD SMALL BRIDGE TO MAIN JAVASCRIPT"

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)

$bridgePattern = '(?s)\r?\n?\s*window\.BrowserNoteBridge\s*=\s*\{.*?\};\s*(?=\r?\n\s*boot\(\);)'
$mainJs = [regex]::Replace($mainJs, $bridgePattern, '')

$bridgeCode = @'

    window.BrowserNoteBridge = {
        async openNoteById(id, mode = 'active') {
            await flushPendingSave();

            state.mode = mode === 'archived'
                ? 'archived'
                : 'active';

            state.folderFilter = 'all';

            updateModeUI();
            renderFolders();
            renderNotes();

            await openNote(Number(id));
        },

        refresh() {
            updateModeUI();
            renderFolders();
            renderNotes();
        },

        getMode() {
            return state.mode;
        },

        getCurrentId() {
            return state.currentId;
        },
    };
'@

$bootPattern = '(?m)^(\s*)boot\(\);\s*$'
$bootMatch = [regex]::Match($mainJs, $bootPattern)

if (-not $bootMatch.Success) {
    Fail "Marker boot(); tidak ditemukan pada browsernote.js."
}

$replacement = $bridgeCode.Replace("`n", "`r`n") + "`r`n" + $bootMatch.Groups[1].Value + 'boot();'
$mainJs = [regex]::Replace($mainJs, $bootPattern, $replacement, 1)

Write-Utf8NoBom -Path $MainJsPath -Content $mainJs

Ok "BrowserNoteBridge dipasang"

Step "7. CREATE STANDALONE SEARCH JAVASCRIPT"

$searchJs = @'
(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiUrl = `${config.baseUrl}/api/search`;
    const debounceMs = 240;

    const input = document.getElementById('searchInput');
    const clearButton = document.getElementById('searchClearButton');
    const noteList = document.getElementById('noteList');
    const noteCount = document.getElementById('noteCount');
    const heading = document.getElementById('noteListHeading');

    if (!input || !clearButton || !noteList || !noteCount || !heading) {
        console.error('BrowserNote Search UI tidak lengkap.');
        return;
    }

    let timer = null;
    let requestSeq = 0;
    let query = '';
    let results = [];

    function bridge() {
        return window.BrowserNoteBridge || null;
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

    function hasQuery() {
        return query.trim() !== '';
    }

    function focusSearch() {
        input.focus();
        input.select();
    }

    function restoreNormalList() {
        heading.textContent = 'CATATAN';

        if (bridge()) {
            bridge().refresh();
        }
    }

    function clearSearch({ keepFocus = false } = {}) {
        window.clearTimeout(timer);
        timer = null;
        requestSeq += 1;

        query = '';
        results = [];

        input.value = '';
        clearButton.hidden = true;

        restoreNormalList();

        if (keepFocus) {
            input.focus();
        }
    }

    async function apiSearch(value) {
        const response = await fetch(
            `${apiUrl}?q=${encodeURIComponent(value)}&status=all&limit=100`,
            {
                headers: {
                    Accept: 'application/json',
                },
            }
        );

        const data = await response.json();

        if (!response.ok || !data?.ok) {
            throw new Error(
                data?.message || `HTTP ${response.status}`
            );
        }

        return data;
    }

    function renderResults() {
        heading.textContent = 'HASIL PENCARIAN';
        noteList.innerHTML = '';
        noteCount.textContent = String(results.length);

        if (results.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'mode-empty';
            empty.textContent =
                `Tidak ditemukan catatan untuk "${query}".`;

            noteList.appendChild(empty);
            return;
        }

        for (const note of results) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'note-item search-result';

            const title = document.createElement('div');
            title.className = 'note-item-title';
            title.textContent =
                note.title || 'Catatan tanpa judul';

            const meta = document.createElement('div');
            meta.className = 'note-item-meta';

            const status = Number(note.is_archived) === 1
                ? 'Arsip'
                : 'Aktif';

            const folder = note.folder_name
                ? ` · ${note.folder_name}`
                : '';

            meta.textContent =
                `${status}${folder} · ${formatDate(note.updated_at)}`;

            button.append(title, meta);

            if (note.snippet) {
                const snippet = document.createElement('div');
                snippet.className = 'search-result-snippet';
                snippet.textContent = note.snippet;
                button.appendChild(snippet);
            }

            button.addEventListener('click', async () => {
                const app = bridge();

                if (!app) {
                    return;
                }

                try {
                    const mode = Number(note.is_archived) === 1
                        ? 'archived'
                        : 'active';

                    await app.openNoteById(note.id, mode);
                    clearSearch();
                } catch (error) {
                    console.error(error);
                }
            });

            noteList.appendChild(button);
        }
    }

    async function performSearch(value) {
        const clean = String(value || '').trim();

        if (clean === '') {
            clearSearch();
            return;
        }

        const seq = ++requestSeq;

        heading.textContent = 'HASIL PENCARIAN';
        noteList.innerHTML =
            '<div class="sidebar-empty">Mencari...</div>';
        noteCount.textContent = '…';

        try {
            const data = await apiSearch(clean);

            if (
                seq !== requestSeq
                || clean !== query
            ) {
                return;
            }

            results = Array.isArray(data.data)
                ? data.data
                : [];

            renderResults();
        } catch (error) {
            console.error(error);

            if (seq !== requestSeq) {
                return;
            }

            noteList.innerHTML =
                '<div class="sidebar-empty">Pencarian gagal.</div>';

            noteCount.textContent = '!';
        }
    }

    function scheduleSearch() {
        window.clearTimeout(timer);

        query = input.value.trim();
        clearButton.hidden = query === '';

        if (!hasQuery()) {
            clearSearch();
            return;
        }

        timer = window.setTimeout(() => {
            timer = null;
            performSearch(query);
        }, debounceMs);
    }

    function attachEditorShortcut() {
        if (!window.tinymce) {
            return;
        }

        const editor = window.tinymce.get('noteEditor');

        if (!editor || editor.__browserNoteSearchBound) {
            return;
        }

        editor.__browserNoteSearchBound = true;

        editor.on('keydown', (event) => {
            if (
                (event.ctrlKey || event.metaKey)
                && event.key.toLowerCase() === 'f'
            ) {
                event.preventDefault();
                focusSearch();
            }
        });
    }

    input.addEventListener('input', scheduleSearch);

    input.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            event.preventDefault();
            clearSearch({ keepFocus: true });
        }

        if (
            event.key === 'Enter'
            && results.length > 0
        ) {
            event.preventDefault();

            const first = results[0];
            const app = bridge();

            if (!app) {
                return;
            }

            const mode = Number(first.is_archived) === 1
                ? 'archived'
                : 'active';

            app.openNoteById(first.id, mode)
                .then(() => clearSearch())
                .catch(console.error);
        }
    });

    clearButton.addEventListener('click', () => {
        clearSearch({ keepFocus: true });
    });

    document.addEventListener('keydown', (event) => {
        if (
            (event.ctrlKey || event.metaKey)
            && event.key.toLowerCase() === 'f'
        ) {
            event.preventDefault();
            focusSearch();
            return;
        }

        if (
            event.key === 'Escape'
            && hasQuery()
            && document.activeElement !== input
        ) {
            clearSearch();
        }
    });

    const shortcutTimer = window.setInterval(() => {
        attachEditorShortcut();

        if (
            window.tinymce
            && window.tinymce.get('noteEditor')
        ) {
            window.clearInterval(shortcutTimer);
        }
    }, 250);

    window.BrowserNoteSearch = {
        focus: focusSearch,

        clear() {
            clearSearch();
        },

        run(value) {
            input.value = String(value || '');
            query = input.value.trim();
            clearButton.hidden = query === '';

            return performSearch(query);
        },

        getQuery() {
            return query;
        },

        getResults() {
            return [...results];
        },
    };
})();
'@

Write-Utf8NoBom -Path $SearchJsPath -Content $searchJs

Ok "search.js dibuat"

Step "8. APPEND SEARCH CSS"

$cssText = [System.IO.File]::ReadAllText($CssPath)
$cssMarker = '/* BROWSERNOTE_STAGE09_SEARCH */'

if ($cssText.Contains($cssMarker)) {
    $cssText = $cssText.Substring(
        0,
        $cssText.IndexOf($cssMarker)
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
    cursor: pointer;
}

.search-clear:hover {
    background: var(--surface-hover);
    color: var(--text);
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

$combinedCss = $cssText.TrimEnd() + "`r`n" + $searchCss.Trim() + "`r`n"
Write-Utf8NoBom -Path $CssPath -Content $combinedCss

Ok "CSS Search dipasang"

Step "9. PHP LINT"

foreach ($file in @($SearchApi, $RoutesPath, $ViewPath)) {
    $lint = & $PhpExe -l $file 2>&1

    if ($LASTEXITCODE -ne 0) {
        $lint | ForEach-Object { Write-Host $_ }
        Fail "PHP lint gagal: $file"
    }

    Ok "Syntax valid: $(Split-Path $file -Leaf)"
}

Step "10. ROUTE VERIFICATION"

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

$routesJoined = $routesOut -join "`n"

if ($routesJoined -notlike '*SearchApi::index*') {
    Fail "Route SearchApi::index tidak terdaftar."
}

Ok "Search route PASS"

Step "11. SEARCH API WORKFLOW TEST"

$testId = $null
$token = "Stage09Needle$([Guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    $created = Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes" -Body @{
        title = '__STAGE09_SEARCH_TEST__'
        content = "<p>BrowserNote content search $token konfigurasi SMTP 587.</p>"
    }

    $testId = [int]$created.data.id

    $titleQuery = [uri]::EscapeDataString('__STAGE09_SEARCH_TEST__')
    $titleSearch = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/search?q=$titleQuery&status=all"

    $titleHit = @($titleSearch.data | Where-Object { [int]$_.id -eq $testId })

    if ($titleHit.Count -lt 1) {
        Fail "Search berdasarkan judul gagal."
    }

    $contentQuery = [uri]::EscapeDataString($token)
    $contentSearch = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/search?q=$contentQuery&status=all"

    $contentHit = @($contentSearch.data | Where-Object { [int]$_.id -eq $testId })

    if ($contentHit.Count -lt 1) {
        Fail "Search berdasarkan isi gagal."
    }

    if (-not $contentHit[0].snippet) {
        Fail "Snippet hasil search tidak tersedia."
    }

    Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes/$testId/archive" | Out-Null

    $archiveSearch = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/search?q=$contentQuery&status=all"
    $archiveHit = @($archiveSearch.data | Where-Object { [int]$_.id -eq $testId })

    if ($archiveHit.Count -lt 1) {
        Fail "Catatan arsip tidak ditemukan."
    }

    if ([int]$archiveHit[0].is_archived -ne 1) {
        Fail "Status hasil arsip tidak sesuai."
    }

    Invoke-Json -Method 'POST' -Uri "$BaseUrl/api/notes/$testId/restore-archive" | Out-Null
    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId" | Out-Null

    $trashSearch = Invoke-Json -Method 'GET' -Uri "$BaseUrl/api/search?q=$contentQuery&status=all"
    $trashHit = @($trashSearch.data | Where-Object { [int]$_.id -eq $testId })

    if ($trashHit.Count -gt 0) {
        Fail "Catatan Sampah masih muncul pada pencarian."
    }

    Invoke-Json -Method 'DELETE' -Uri "$BaseUrl/api/notes/$testId/force" | Out-Null

    $testId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Search API workflow test gagal."
}

Ok "Search title PASS"
Ok "Search content PASS"
Ok "Snippet PASS"
Ok "Archived searchable PASS"
Ok "Trash excluded PASS"
Ok "Test cleanup PASS"

Step "12. HTTP UI VERIFICATION"

try {
    $page = Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 8
    $searchJsHttp = Invoke-WebRequest -Uri "$BaseUrl/assets/js/search.js" -UseBasicParsing -TimeoutSec 8
    $mainJsHttp = Invoke-WebRequest -Uri "$BaseUrl/assets/js/browsernote.js" -UseBasicParsing -TimeoutSec 8
}
catch {
    Fail "Root atau aset Search tidak dapat diakses melalui Apache."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if ($searchJsHttp.StatusCode -ne 200) {
    Fail "search.js tidak HTTP 200."
}

if ($mainJsHttp.StatusCode -ne 200) {
    Fail "browsernote.js tidak HTTP 200."
}

foreach ($fragment in @(
    'id="searchInput"',
    'id="searchClearButton"',
    'assets/js/search.js'
)) {
    if ($page.Content -notlike "*$fragment*") {
        Fail "Elemen Search tidak tersedia: $fragment"
    }
}

if ($mainJsHttp.Content -notlike '*window.BrowserNoteBridge*') {
    Fail "BrowserNoteBridge tidak tersedia."
}

if ($searchJsHttp.Content -notlike '*window.BrowserNoteSearch*') {
    Fail "BrowserNoteSearch tidak tersedia."
}

Ok "Search UI tersedia melalui Apache"
Ok "BrowserNoteBridge tersedia"
Ok "search.js tersedia"

Step "STAGE 09C PASS - STAGE 09 COMPLETE"

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
Write-Host "1. Cari kata pada judul catatan." -ForegroundColor White
Write-Host "2. Cari kata yang hanya ada di isi catatan." -ForegroundColor White
Write-Host "3. Pastikan snippet isi muncul." -ForegroundColor White
Write-Host "4. Arsipkan catatan lalu cari isinya." -ForegroundColor White
Write-Host "5. Klik hasil Arsip dan pastikan catatan terbuka." -ForegroundColor White
Write-Host "6. Tekan Ctrl+F dan pastikan fokus ke pencarian." -ForegroundColor White
Write-Host "7. Tekan Esc untuk membersihkan pencarian." -ForegroundColor White
Write-Host "8. Pastikan catatan Sampah tidak ditemukan." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 10 - Quick Note + keyboard shortcuts final" -ForegroundColor Green
