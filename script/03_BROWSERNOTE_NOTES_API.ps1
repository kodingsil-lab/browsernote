#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 03 NOTES API
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'
$ApiBase     = "$BaseUrl/api/notes"
$RoutesPath  = Join-Path $ProjectRoot 'app\Config\Routes.php'
$ApiDir      = Join-Path $ProjectRoot 'app\Controllers\Api'
$ApiFile     = Join-Path $ApiDir 'NotesApi.php'
$BackupRoot  = Join-Path $ProjectRoot 'writable\backups'
$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "stage03_$Stamp"

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

function Remove-Utf8Bom {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF) {

        $newBytes = New-Object byte[] ($bytes.Length - 3)
        [Array]::Copy($bytes, 3, $newBytes, 0, $bytes.Length - 3)
        [System.IO.File]::WriteAllBytes($Path, $newBytes)
        return $true
    }

    return $false
}

function Backup-File {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    $relative = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $destination = Join-Path $BackupDir $relative
    $destinationDir = Split-Path $destination -Parent

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item $Path $destination -Force
}

function Invoke-JsonRequest {
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

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "spark tidak ditemukan."
}

if (-not (Test-Path $RoutesPath)) {
    Fail "Routes.php tidak ditemukan."
}

if (-not (Test-Path (Join-Path $ProjectRoot 'app\Models\NoteModel.php'))) {
    Fail "NoteModel.php tidak ditemukan. Stage 02 belum lengkap."
}

if (-not (Test-Path (Join-Path $ProjectRoot 'app\Models\FolderModel.php'))) {
    Fail "FolderModel.php tidak ditemukan. Stage 02 belum lengkap."
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

Ok "Project ditemukan"
Ok "PHP ditemukan: $PhpExe"
Ok "NoteModel ditemukan"
Ok "FolderModel ditemukan"

Step "2. BACKUP FILES"

Backup-File $RoutesPath
Backup-File $ApiFile

if (Test-Path $BackupDir) {
    Ok "Backup dibuat: $BackupDir"
} else {
    Warn "Tidak ada file Stage 03 lama yang perlu dibackup selain route baru."
}

Step "3. REMOVE UTF-8 BOM FROM APP PHP FILES"

$appPhpFiles = Get-ChildItem (Join-Path $ProjectRoot 'app') -Filter '*.php' -Recurse -File
$bomCount = 0

foreach ($file in $appPhpFiles) {
    if (Remove-Utf8Bom -Path $file.FullName) {
        $bomCount++
        Write-Host "[FIX]  BOM dihapus: $($file.FullName)" -ForegroundColor Yellow
    }
}

Ok "Pembersihan BOM selesai. File diperbaiki: $bomCount"

Step "4. CREATE NOTES API CONTROLLER"

New-Item -ItemType Directory -Path $ApiDir -Force | Out-Null

$apiCode = @'
<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use App\Models\FolderModel;
use App\Models\NoteModel;
use CodeIgniter\HTTP\ResponseInterface;

class NotesApi extends BaseController
{
    private NoteModel $notes;
    private FolderModel $folders;

    public function __construct()
    {
        $this->notes = new NoteModel();
        $this->folders = new FolderModel();
    }

    public function index()
    {
        $status = strtolower(trim((string) $this->request->getGet('status')));
        $status = $status !== '' ? $status : 'active';

        $builder = db_connect()
            ->table('notes n')
            ->select('n.*, f.name AS folder_name')
            ->join('folders f', 'f.id = n.folder_id', 'left');

        switch ($status) {
            case 'active':
                $builder
                    ->where('n.is_deleted', 0)
                    ->where('n.is_archived', 0);
                break;

            case 'archived':
                $builder
                    ->where('n.is_deleted', 0)
                    ->where('n.is_archived', 1);
                break;

            case 'trash':
                $builder->where('n.is_deleted', 1);
                break;

            case 'all':
                break;

            default:
                return $this->json([
                    'ok'      => false,
                    'message' => 'Status tidak valid.',
                ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        $rows = $builder
            ->orderBy('n.updated_at', 'DESC')
            ->orderBy('n.id', 'DESC')
            ->limit(200)
            ->get()
            ->getResultArray();

        return $this->json([
            'ok'     => true,
            'status' => $status,
            'count'  => count($rows),
            'data'   => $rows,
        ]);
    }

    public function show(int $id)
    {
        $note = $this->findWithFolder($id);

        if ($note === null) {
            return $this->notFound();
        }

        return $this->json([
            'ok'   => true,
            'data' => $note,
        ]);
    }

    public function create()
    {
        $payload = $this->payload();

        $folderId = $this->normalizeFolderId($payload['folder_id'] ?? null);

        if ($folderId === false) {
            return $this->json([
                'ok'      => false,
                'message' => 'Folder tidak ditemukan.',
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        $title = $this->normalizeTitle($payload['title'] ?? null);
        $content = (string) ($payload['content'] ?? '');

        $id = $this->notes->insert([
            'folder_id'    => $folderId,
            'title'        => $title,
            'content'      => $content,
            'content_text' => $this->plainText($content),
            'is_archived'  => 0,
            'is_deleted'   => 0,
            'archived_at'  => null,
            'deleted_at'   => null,
        ], true);

        if (!$id) {
            return $this->json([
                'ok'      => false,
                'message' => 'Catatan gagal dibuat.',
                'errors'  => $this->notes->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dibuat.',
            'data'    => $this->findWithFolder((int) $id),
        ], ResponseInterface::HTTP_CREATED);
    }

    public function update(int $id)
    {
        $current = $this->notes->find($id);

        if ($current === null) {
            return $this->notFound();
        }

        $payload = $this->payload();
        $data = [];

        if (array_key_exists('folder_id', $payload)) {
            $folderId = $this->normalizeFolderId($payload['folder_id']);

            if ($folderId === false) {
                return $this->json([
                    'ok'      => false,
                    'message' => 'Folder tidak ditemukan.',
                ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
            }

            $data['folder_id'] = $folderId;
        }

        if (array_key_exists('title', $payload)) {
            $data['title'] = $this->normalizeTitle($payload['title']);
        }

        if (array_key_exists('content', $payload)) {
            $content = (string) $payload['content'];
            $data['content'] = $content;
            $data['content_text'] = $this->plainText($content);
        }

        if ($data === []) {
            return $this->json([
                'ok'      => false,
                'message' => 'Tidak ada perubahan yang dikirim.',
            ], ResponseInterface::HTTP_BAD_REQUEST);
        }

        if (!$this->notes->update($id, $data)) {
            return $this->json([
                'ok'      => false,
                'message' => 'Catatan gagal diperbarui.',
                'errors'  => $this->notes->errors(),
            ], ResponseInterface::HTTP_UNPROCESSABLE_ENTITY);
        }

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan diperbarui.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function archive(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        if ((int) $note['is_deleted'] === 1) {
            return $this->json([
                'ok'      => false,
                'message' => 'Catatan di Sampah tidak dapat langsung diarsipkan.',
            ], ResponseInterface::HTTP_CONFLICT);
        }

        $this->notes->update($id, [
            'is_archived' => 1,
            'archived_at' => date('Y-m-d H:i:s'),
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan diarsipkan.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function restoreArchive(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        $this->notes->update($id, [
            'is_archived' => 0,
            'archived_at' => null,
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dikembalikan dari Arsip.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function trash(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        $this->notes->update($id, [
            'is_deleted'  => 1,
            'deleted_at'  => date('Y-m-d H:i:s'),
            'is_archived' => 0,
            'archived_at' => null,
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dipindahkan ke Sampah.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function restoreTrash(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        $this->notes->update($id, [
            'is_deleted' => 0,
            'deleted_at' => null,
        ]);

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dipulihkan dari Sampah.',
            'data'    => $this->findWithFolder($id),
        ]);
    }

    public function forceDelete(int $id)
    {
        $note = $this->notes->find($id);

        if ($note === null) {
            return $this->notFound();
        }

        if ((int) $note['is_deleted'] !== 1) {
            return $this->json([
                'ok'      => false,
                'message' => 'Hapus permanen hanya diperbolehkan untuk catatan yang sudah berada di Sampah.',
            ], ResponseInterface::HTTP_CONFLICT);
        }

        db_connect()
            ->table('notes')
            ->where('id', $id)
            ->delete();

        return $this->json([
            'ok'      => true,
            'message' => 'Catatan dihapus permanen.',
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

    private function normalizeTitle(mixed $title): string
    {
        $title = trim((string) $title);

        if ($title === '') {
            return 'Catatan tanpa judul';
        }

        return mb_substr($title, 0, 255);
    }

    private function normalizeFolderId(mixed $folderId): int|null|false
    {
        if ($folderId === null || $folderId === '') {
            return null;
        }

        if (!is_numeric($folderId)) {
            return false;
        }

        $folderId = (int) $folderId;

        if ($folderId < 1 || $this->folders->find($folderId) === null) {
            return false;
        }

        return $folderId;
    }

    private function plainText(string $html): string
    {
        $text = html_entity_decode(
            strip_tags($html),
            ENT_QUOTES | ENT_HTML5,
            'UTF-8'
        );

        $text = preg_replace('/\s+/u', ' ', $text) ?? $text;

        return trim($text);
    }

    private function findWithFolder(int $id): ?array
    {
        $row = db_connect()
            ->table('notes n')
            ->select('n.*, f.name AS folder_name')
            ->join('folders f', 'f.id = n.folder_id', 'left')
            ->where('n.id', $id)
            ->get()
            ->getRowArray();

        return $row ?: null;
    }

    private function notFound()
    {
        return $this->json([
            'ok'      => false,
            'message' => 'Catatan tidak ditemukan.',
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

Write-Utf8NoBom -Path $ApiFile -Content $apiCode
Ok "NotesApi.php dibuat"

Step "5. PATCH ROUTES"

$routesText = [System.IO.File]::ReadAllText($RoutesPath)

$startMarker = '// <BROWSERNOTE_STAGE03_API>'
$endMarker   = '// </BROWSERNOTE_STAGE03_API>'

$pattern = '(?s)\r?\n?' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker) + '\r?\n?'
$routesText = [regex]::Replace($routesText, $pattern, "`r`n")

$routeBlock = @'

// <BROWSERNOTE_STAGE03_API>
$routes->group('api', static function ($routes) {
    $routes->get('notes', 'Api\NotesApi::index');
    $routes->post('notes', 'Api\NotesApi::create');

    $routes->get('notes/(:num)', 'Api\NotesApi::show/$1');
    $routes->patch('notes/(:num)', 'Api\NotesApi::update/$1');

    $routes->post('notes/(:num)/archive', 'Api\NotesApi::archive/$1');
    $routes->post('notes/(:num)/restore-archive', 'Api\NotesApi::restoreArchive/$1');

    $routes->post('notes/(:num)/restore-trash', 'Api\NotesApi::restoreTrash/$1');
    $routes->delete('notes/(:num)/force', 'Api\NotesApi::forceDelete/$1');
    $routes->delete('notes/(:num)', 'Api\NotesApi::trash/$1');
});
// </BROWSERNOTE_STAGE03_API>
'@

$routesText = $routesText.TrimEnd() + "`r`n" + $routeBlock.Trim() + "`r`n"
Write-Utf8NoBom -Path $RoutesPath -Content $routesText

Ok "Routes API ditambahkan"

Step "6. PHP LINT"

$lintTargets = @(
    $ApiFile,
    $RoutesPath,
    (Join-Path $ProjectRoot 'app\Models\NoteModel.php'),
    (Join-Path $ProjectRoot 'app\Models\FolderModel.php')
)

foreach ($file in $lintTargets) {
    $lint = & $PhpExe -l $file 2>&1

    if ($LASTEXITCODE -ne 0) {
        $lint | ForEach-Object { Write-Host $_ }
        Fail "PHP lint gagal: $file"
    }

    Ok "Syntax valid: $(Split-Path $file -Leaf)"
}

Step "7. VERIFY ROUTES"

Push-Location $ProjectRoot
try {
    $routeOutput = & $PhpExe spark routes 2>&1
    $routeExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($routeExit -ne 0) {
    $routeOutput | ForEach-Object { Write-Host $_ }
    Fail "php spark routes gagal."
}

$routeTextJoined = $routeOutput -join "`n"

$requiredRouteFragments = @(
    'api/notes',
    'NotesApi::index',
    'NotesApi::create',
    'NotesApi::show',
    'NotesApi::update',
    'NotesApi::archive',
    'NotesApi::restoreArchive',
    'NotesApi::restoreTrash',
    'NotesApi::forceDelete',
    'NotesApi::trash'
)

foreach ($fragment in $requiredRouteFragments) {
    if ($routeTextJoined -notlike "*$fragment*") {
        Fail "Route belum terdaftar: $fragment"
    }
}

Ok "Semua route Notes API terdaftar"

Step "8. HTTP PRECHECK"

try {
    $root = Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 5
    if ($root.StatusCode -ne 200) {
        Fail "Root BrowserNote merespons status $($root.StatusCode)."
    }
}
catch {
    Fail "BrowserNote tidak dapat diakses melalui Apache. Pastikan Apache XAMPP aktif. URL: $BaseUrl/"
}

Ok "Apache / BrowserNote HTTP aktif"

Step "9. GET NOTES API TEST"

try {
    $list = Invoke-JsonRequest -Method 'GET' -Uri $ApiBase
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "GET /api/notes gagal."
}

if (-not $list.ok) {
    Fail "GET /api/notes mengembalikan ok=false."
}

Ok "GET /api/notes PASS"
Write-Host "       Active notes: $($list.count)" -ForegroundColor DarkGray

Step "10. CREATE NOTE API TEST"

$testId = $null

try {
    $created = Invoke-JsonRequest -Method 'POST' -Uri $ApiBase -Body @{
        title   = '__STAGE03_API_TEST__'
        content = '<h2>Stage 03</h2><p>API create test.</p>'
    }

    if (-not $created.ok -or -not $created.data.id) {
        Fail "POST /api/notes tidak mengembalikan ID."
    }

    $testId = [int] $created.data.id
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "POST /api/notes gagal."
}

Ok "CREATE API PASS - id=$testId"

Step "11. READ + UPDATE API TEST"

try {
    $shown = Invoke-JsonRequest -Method 'GET' -Uri "$ApiBase/$testId"

    if (-not $shown.ok -or $shown.data.title -ne '__STAGE03_API_TEST__') {
        Fail "GET catatan tunggal gagal diverifikasi."
    }

    $updated = Invoke-JsonRequest -Method 'PATCH' -Uri "$ApiBase/$testId" -Body @{
        title   = '__STAGE03_API_TEST_UPDATED__'
        content = '<p>Updated content 123.</p>'
    }

    if (-not $updated.ok -or $updated.data.title -ne '__STAGE03_API_TEST_UPDATED__') {
        Fail "PATCH catatan gagal diverifikasi."
    }

    if ($updated.data.content_text -ne 'Updated content 123.') {
        Fail "content_text otomatis tidak sesuai."
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "READ/UPDATE API gagal."
}

Ok "READ API PASS"
Ok "UPDATE API PASS"
Ok "HTML -> content_text PASS"

Step "12. ARCHIVE + RESTORE API TEST"

try {
    $archived = Invoke-JsonRequest -Method 'POST' -Uri "$ApiBase/$testId/archive"

    if (-not $archived.ok -or [int] $archived.data.is_archived -ne 1) {
        Fail "Archive gagal."
    }

    $restoredArchive = Invoke-JsonRequest -Method 'POST' -Uri "$ApiBase/$testId/restore-archive"

    if (-not $restoredArchive.ok -or [int] $restoredArchive.data.is_archived -ne 0) {
        Fail "Restore archive gagal."
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Archive/restore archive API gagal."
}

Ok "ARCHIVE API PASS"
Ok "RESTORE ARCHIVE API PASS"

Step "13. TRASH + RESTORE + FORCE DELETE TEST"

try {
    $trashed = Invoke-JsonRequest -Method 'DELETE' -Uri "$ApiBase/$testId"

    if (-not $trashed.ok -or [int] $trashed.data.is_deleted -ne 1) {
        Fail "Trash gagal."
    }

    $restoredTrash = Invoke-JsonRequest -Method 'POST' -Uri "$ApiBase/$testId/restore-trash"

    if (-not $restoredTrash.ok -or [int] $restoredTrash.data.is_deleted -ne 0) {
        Fail "Restore trash gagal."
    }

    $trashedAgain = Invoke-JsonRequest -Method 'DELETE' -Uri "$ApiBase/$testId"

    if (-not $trashedAgain.ok -or [int] $trashedAgain.data.is_deleted -ne 1) {
        Fail "Trash kedua gagal."
    }

    $forced = Invoke-JsonRequest -Method 'DELETE' -Uri "$ApiBase/$testId/force"

    if (-not $forced.ok -or [int] $forced.id -ne $testId) {
        Fail "Force delete gagal."
    }

    $testId = $null
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Trash/restore/force delete API gagal."
}

Ok "TRASH API PASS"
Ok "RESTORE TRASH API PASS"
Ok "FORCE DELETE API PASS"

Step "14. VERIFY TEST NOTE CLEANUP"

try {
    $allNotes = Invoke-JsonRequest -Method 'GET' -Uri "$ApiBase?status=all"

    $leftover = @($allNotes.data | Where-Object {
        $_.title -eq '__STAGE03_API_TEST__' -or
        $_.title -eq '__STAGE03_API_TEST_UPDATED__'
    })

    if ($leftover.Count -gt 0) {
        Fail "Catatan test Stage 03 masih tersisa."
    }
}
catch {
    Fail "Verifikasi cleanup Stage 03 gagal."
}

Ok "Tidak ada data test yang tertinggal"

Step "STAGE 03 PASS"

Write-Host ""
Write-Host "Project    : $ProjectRoot" -ForegroundColor White
Write-Host "API Base   : $ApiBase" -ForegroundColor White
Write-Host "List       : PASS" -ForegroundColor White
Write-Host "Create     : PASS" -ForegroundColor White
Write-Host "Read       : PASS" -ForegroundColor White
Write-Host "Update     : PASS" -ForegroundColor White
Write-Host "Archive    : PASS" -ForegroundColor White
Write-Host "Trash      : PASS" -ForegroundColor White
Write-Host "Restore    : PASS" -ForegroundColor White
Write-Host "Force Del. : PASS" -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 04 - TinyMCE Self-Hosted + Full Rich Editor" -ForegroundColor Green
