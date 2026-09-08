#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 02 DATABASE + MODELS
# Target  : C:\xampp\htdocs\browsernote
# Database: writable\browsernote.sqlite
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
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

function Resolve-PHP {
    $cmd = Get-Command php -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $xamppPhp = 'C:\xampp\php\php.exe'
    if (Test-Path $xamppPhp) { return $xamppPhp }

    return $null
}

function Backup-IfExists {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (Test-Path $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupDir = Join-Path $ProjectRoot "writable\backups\stage02_$stamp"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        $leaf = Split-Path $Path -Leaf
        Copy-Item $Path (Join-Path $backupDir $leaf) -Force

        Ok "Backup dibuat: $leaf"
    }
}

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "spark tidak ditemukan. Stage 01 belum valid."
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}
Ok "PHP ditemukan: $PhpExe"

$modules = & $PhpExe -m
if ($modules -notcontains 'sqlite3') {
    Fail "Ekstensi sqlite3 belum aktif."
}
Ok "SQLite3 aktif"

if (-not (Test-Path $DbFile)) {
    Fail "Database SQLite belum ditemukan: $DbFile"
}
Ok "Database ditemukan: $DbFile"

Step "2. PREPARE DIRECTORIES"

$MigrationDir = Join-Path $ProjectRoot 'app\Database\Migrations'
$SeedDir      = Join-Path $ProjectRoot 'app\Database\Seeds'
$ModelDir     = Join-Path $ProjectRoot 'app\Models'

New-Item -ItemType Directory -Path $MigrationDir -Force | Out-Null
New-Item -ItemType Directory -Path $SeedDir -Force | Out-Null
New-Item -ItemType Directory -Path $ModelDir -Force | Out-Null

Ok "Folder migrations siap"
Ok "Folder seeds siap"
Ok "Folder models siap"

Step "3. CREATE MIGRATIONS"

$FoldersMigration = Join-Path $MigrationDir '2026-09-08-000001_CreateFolders.php'
$NotesMigration   = Join-Path $MigrationDir '2026-09-08-000002_CreateNotes.php'

Backup-IfExists $FoldersMigration
Backup-IfExists $NotesMigration

$foldersCode = @'
<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

class CreateFolders extends Migration
{
    public function up()
    {
        $this->forge->addField([
            'id' => [
                'type'           => 'INTEGER',
                'unsigned'       => true,
                'auto_increment' => true,
            ],
            'name' => [
                'type'       => 'VARCHAR',
                'constraint' => 150,
            ],
            'sort_order' => [
                'type'       => 'INTEGER',
                'default'    => 0,
            ],
            'created_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'updated_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
        ]);

        $this->forge->addKey('id', true);
        $this->forge->addKey('name');
        $this->forge->createTable('folders', true);
    }

    public function down()
    {
        $this->forge->dropTable('folders', true);
    }
}
'@
Set-Content -Path $FoldersMigration -Value $foldersCode -Encoding UTF8

$notesCode = @'
<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

class CreateNotes extends Migration
{
    public function up()
    {
        $this->forge->addField([
            'id' => [
                'type'           => 'INTEGER',
                'unsigned'       => true,
                'auto_increment' => true,
            ],
            'folder_id' => [
                'type'     => 'INTEGER',
                'unsigned' => true,
                'null'     => true,
            ],
            'title' => [
                'type'       => 'VARCHAR',
                'constraint' => 255,
                'default'    => 'Catatan tanpa judul',
            ],
            'content' => [
                'type' => 'TEXT',
                'null' => true,
            ],
            'content_text' => [
                'type' => 'TEXT',
                'null' => true,
            ],
            'is_archived' => [
                'type'    => 'INTEGER',
                'default' => 0,
            ],
            'is_deleted' => [
                'type'    => 'INTEGER',
                'default' => 0,
            ],
            'archived_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'deleted_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'created_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
            'updated_at' => [
                'type' => 'DATETIME',
                'null' => true,
            ],
        ]);

        $this->forge->addKey('id', true);
        $this->forge->addKey('folder_id');
        $this->forge->addKey('title');
        $this->forge->addKey('is_archived');
        $this->forge->addKey('is_deleted');

        $this->forge->addForeignKey(
            'folder_id',
            'folders',
            'id',
            'SET NULL',
            'CASCADE'
        );

        $this->forge->createTable('notes', true);
    }

    public function down()
    {
        $this->forge->dropTable('notes', true);
    }
}
'@
Set-Content -Path $NotesMigration -Value $notesCode -Encoding UTF8

Ok "Migration folders dibuat"
Ok "Migration notes dibuat"

Step "4. CREATE MODELS"

$FolderModelPath = Join-Path $ModelDir 'FolderModel.php'
$NoteModelPath   = Join-Path $ModelDir 'NoteModel.php'

Backup-IfExists $FolderModelPath
Backup-IfExists $NoteModelPath

$folderModelCode = @'
<?php

namespace App\Models;

use CodeIgniter\Model;

class FolderModel extends Model
{
    protected $table            = 'folders';
    protected $primaryKey       = 'id';
    protected $returnType       = 'array';
    protected $useAutoIncrement = true;

    protected $allowedFields = [
        'name',
        'sort_order',
    ];

    protected $useTimestamps = true;
    protected $createdField  = 'created_at';
    protected $updatedField  = 'updated_at';

    protected $validationRules = [
        'name' => 'required|max_length[150]',
    ];
}
'@
Set-Content -Path $FolderModelPath -Value $folderModelCode -Encoding UTF8

$noteModelCode = @'
<?php

namespace App\Models;

use CodeIgniter\Model;

class NoteModel extends Model
{
    protected $table            = 'notes';
    protected $primaryKey       = 'id';
    protected $returnType       = 'array';
    protected $useAutoIncrement = true;

    protected $allowedFields = [
        'folder_id',
        'title',
        'content',
        'content_text',
        'is_archived',
        'is_deleted',
        'archived_at',
        'deleted_at',
    ];

    protected $useTimestamps = true;
    protected $createdField  = 'created_at';
    protected $updatedField  = 'updated_at';

    protected $validationRules = [
        'title' => 'permit_empty|max_length[255]',
    ];

    public function activeNotes()
    {
        return $this
            ->where('is_deleted', 0)
            ->where('is_archived', 0)
            ->orderBy('updated_at', 'DESC')
            ->findAll();
    }

    public function archivedNotes()
    {
        return $this
            ->where('is_deleted', 0)
            ->where('is_archived', 1)
            ->orderBy('archived_at', 'DESC')
            ->findAll();
    }

    public function trashedNotes()
    {
        return $this
            ->where('is_deleted', 1)
            ->orderBy('deleted_at', 'DESC')
            ->findAll();
    }

    public function searchNotes(string $query)
    {
        return $this
            ->groupStart()
                ->like('title', $query)
                ->orLike('content_text', $query)
            ->groupEnd()
            ->where('is_deleted', 0)
            ->orderBy('updated_at', 'DESC')
            ->findAll();
    }
}
'@
Set-Content -Path $NoteModelPath -Value $noteModelCode -Encoding UTF8

Ok "FolderModel dibuat"
Ok "NoteModel dibuat"

Step "5. CREATE INITIAL SEEDER"

$SeederPath = Join-Path $SeedDir 'BrowserNoteSeeder.php'
Backup-IfExists $SeederPath

$seederCode = @'
<?php

namespace App\Database\Seeds;

use CodeIgniter\Database\Seeder;

class BrowserNoteSeeder extends Seeder
{
    public function run()
    {
        $folderCount = $this->db->table('folders')->countAllResults();
        $noteCount   = $this->db->table('notes')->countAllResults();

        if ($folderCount === 0) {
            $this->db->table('folders')->insert([
                'name'       => 'Umum',
                'sort_order' => 0,
                'created_at' => date('Y-m-d H:i:s'),
                'updated_at' => date('Y-m-d H:i:s'),
            ]);
        }

        if ($noteCount === 0) {
            $folder = $this->db->table('folders')
                ->where('name', 'Umum')
                ->get()
                ->getRowArray();

            $this->db->table('notes')->insert([
                'folder_id'    => $folder['id'] ?? null,
                'title'        => 'Catatan awal',
                'content'      => '<h1>BrowserNote</h1><p>Catatan pertama siap digunakan.</p>',
                'content_text' => 'BrowserNote Catatan pertama siap digunakan.',
                'is_archived'  => 0,
                'is_deleted'   => 0,
                'created_at'   => date('Y-m-d H:i:s'),
                'updated_at'   => date('Y-m-d H:i:s'),
            ]);
        }
    }
}
'@
Set-Content -Path $SeederPath -Value $seederCode -Encoding UTF8

Ok "BrowserNoteSeeder dibuat"

Step "6. RUN MIGRATIONS"

Push-Location $ProjectRoot
try {
    & $PhpExe spark migrate
    if ($LASTEXITCODE -ne 0) {
        Fail "Migration gagal."
    }
} finally {
    Pop-Location
}

Ok "Migration PASS"

Step "7. RUN SEEDER"

Push-Location $ProjectRoot
try {
    & $PhpExe spark db:seed BrowserNoteSeeder
    if ($LASTEXITCODE -ne 0) {
        Fail "Seeder gagal."
    }
} finally {
    Pop-Location
}

Ok "Seeder PASS"

Step "8. PHP LINT VERIFICATION"

$LintTargets = @(
    $FoldersMigration,
    $NotesMigration,
    $FolderModelPath,
    $NoteModelPath,
    $SeederPath
)

foreach ($target in $LintTargets) {
    $lint = & $PhpExe -l $target 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $lint
        Fail "PHP lint gagal: $target"
    }
    Ok "Syntax valid: $(Split-Path $target -Leaf)"
}

Step "9. SQLITE TABLE VERIFICATION"

$dbEscaped = $DbFile.Replace('\', '\\').Replace("'", "\'")
$sqlVerify = @"
`$db = new SQLite3('$dbEscaped');
`$tables = [];
`$r = `$db->query("SELECT name FROM sqlite_master WHERE type='table'");
while (`$row = `$r->fetchArray(SQLITE3_ASSOC)) { `$tables[] = `$row['name']; }
if (!in_array('folders', `$tables, true)) { fwrite(STDERR, "folders missing\n"); exit(31); }
if (!in_array('notes', `$tables, true)) { fwrite(STDERR, "notes missing\n"); exit(32); }
`$fc = `$db->querySingle("SELECT COUNT(*) FROM folders");
`$nc = `$db->querySingle("SELECT COUNT(*) FROM notes");
echo "folders=`$fc\nnotes=`$nc\n";
"@

$verifyOutput = & $PhpExe -r $sqlVerify 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host $verifyOutput
    Fail "Verifikasi tabel SQLite gagal."
}
$verifyOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
Ok "Tabel folders dan notes terverifikasi"

Step "10. SQLITE CRUD VERIFICATION"

$sqlCrud = @"
`$db = new SQLite3('$dbEscaped');
`$db->exec('PRAGMA foreign_keys = ON');
`$now = date('Y-m-d H:i:s');

`$stmt = `$db->prepare('INSERT INTO folders (name, sort_order, created_at, updated_at) VALUES (:name, 9999, :now, :now)');
`$stmt->bindValue(':name', '__STAGE02_TEST__', SQLITE3_TEXT);
`$stmt->bindValue(':now', `$now, SQLITE3_TEXT);
if (!`$stmt->execute()) { fwrite(STDERR, "folder insert failed\n"); exit(41); }
`$folderId = `$db->lastInsertRowID();

`$stmt = `$db->prepare('INSERT INTO notes (folder_id, title, content, content_text, is_archived, is_deleted, created_at, updated_at) VALUES (:folder_id, :title, :content, :content_text, 0, 0, :now, :now)');
`$stmt->bindValue(':folder_id', `$folderId, SQLITE3_INTEGER);
`$stmt->bindValue(':title', '__STAGE02_TEST_NOTE__', SQLITE3_TEXT);
`$stmt->bindValue(':content', '<p>uji</p>', SQLITE3_TEXT);
`$stmt->bindValue(':content_text', 'uji', SQLITE3_TEXT);
`$stmt->bindValue(':now', `$now, SQLITE3_TEXT);
if (!`$stmt->execute()) { fwrite(STDERR, "note insert failed\n"); exit(42); }
`$noteId = `$db->lastInsertRowID();

`$title = `$db->querySingle('SELECT title FROM notes WHERE id=' . (int)`$noteId);
if (`$title !== '__STAGE02_TEST_NOTE__') { fwrite(STDERR, "note read failed\n"); exit(43); }

if (!`$db->exec("UPDATE notes SET title='__STAGE02_TEST_NOTE_UPDATED__' WHERE id=" . (int)`$noteId)) {
    fwrite(STDERR, "note update failed\n"); exit(44);
}

`$title2 = `$db->querySingle('SELECT title FROM notes WHERE id=' . (int)`$noteId);
if (`$title2 !== '__STAGE02_TEST_NOTE_UPDATED__') { fwrite(STDERR, "note update verify failed\n"); exit(45); }

`$db->exec('DELETE FROM notes WHERE id=' . (int)`$noteId);
`$db->exec('DELETE FROM folders WHERE id=' . (int)`$folderId);

echo "CRUD_PASS\n";
"@

$crudOutput = & $PhpExe -r $sqlCrud 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host $crudOutput
    Fail "CRUD SQLite verification gagal."
}
$crudOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
Ok "CRUD SQLite PASS"

Step "STAGE 02 PASS"

Write-Host ""
Write-Host "Project    : $ProjectRoot" -ForegroundColor White
Write-Host "Database   : $DbFile" -ForegroundColor White
Write-Host "Tables     : folders, notes" -ForegroundColor White
Write-Host "Models     : FolderModel, NoteModel" -ForegroundColor White
Write-Host "Seed       : Umum + Catatan awal" -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 03 - Notes API" -ForegroundColor Green
