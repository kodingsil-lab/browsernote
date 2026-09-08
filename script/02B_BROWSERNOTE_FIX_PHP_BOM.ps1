#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 02B
# FIX PHP UTF-8 BOM + RESUME DATABASE SETUP
# Project : C:\xampp\htdocs\browsernote
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

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Remove-Utf8Bom {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF) {

        $newBytes = New-Object byte[] ($bytes.Length - 3)
        [Array]::Copy($bytes, 3, $newBytes, 0, $bytes.Length - 3)
        [System.IO.File]::WriteAllBytes($Path, $newBytes)

        Ok "BOM dihapus: $Path"
    } else {
        Ok "Tanpa BOM: $Path"
    }
}

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "spark tidak ditemukan."
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

Ok "Project ditemukan"
Ok "PHP ditemukan: $PhpExe"

if (-not (Test-Path $DbFile)) {
    Fail "Database SQLite tidak ditemukan: $DbFile"
}
Ok "Database ditemukan: $DbFile"

Step "2. FIX UTF-8 BOM ON STAGE 02 PHP FILES"

$PhpFiles = @(
    (Join-Path $ProjectRoot 'app\Database\Migrations\2026-09-08-000001_CreateFolders.php'),
    (Join-Path $ProjectRoot 'app\Database\Migrations\2026-09-08-000002_CreateNotes.php'),
    (Join-Path $ProjectRoot 'app\Models\FolderModel.php'),
    (Join-Path $ProjectRoot 'app\Models\NoteModel.php'),
    (Join-Path $ProjectRoot 'app\Database\Seeds\BrowserNoteSeeder.php')
)

foreach ($file in $PhpFiles) {
    if (-not (Test-Path $file)) {
        Fail "File Stage 02 tidak ditemukan: $file"
    }

    Remove-Utf8Bom -Path $file
}

Step "3. PHP LINT"

foreach ($file in $PhpFiles) {
    $lint = & $PhpExe -l $file 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host $lint
        Fail "PHP lint gagal: $file"
    }

    Ok "Syntax valid: $(Split-Path $file -Leaf)"
}

Step "4. VERIFY FIRST BYTES"

foreach ($file in $PhpFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file)

    if ($bytes.Length -lt 5) {
        Fail "File terlalu pendek: $file"
    }

    # Expected first bytes: 3C 3F 70 68 70 = <?php
    if (-not (
        $bytes[0] -eq 0x3C -and
        $bytes[1] -eq 0x3F -and
        $bytes[2] -eq 0x70 -and
        $bytes[3] -eq 0x68 -and
        $bytes[4] -eq 0x70
    )) {
        Fail "File tidak dimulai langsung dengan <?php : $file"
    }

    Ok "Header PHP bersih: $(Split-Path $file -Leaf)"
}

Step "5. RUN MIGRATIONS"

Push-Location $ProjectRoot
try {
    & $PhpExe spark migrate
    if ($LASTEXITCODE -ne 0) {
        Fail "Migration gagal."
    }
}
finally {
    Pop-Location
}

Ok "Migration PASS"

Step "6. VERIFY TABLES"

$dbEscaped = $DbFile.Replace('\', '\\').Replace("'", "\'")

$sqlTables = @"
`$db = new SQLite3('$dbEscaped');
`$folders = `$db->querySingle("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='folders'");
`$notes   = `$db->querySingle("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='notes'");
`$migrations = `$db->querySingle("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='migrations'");
echo "folders=`$folders`nnotes=`$notes`nmigrations=`$migrations`n";
if (`$folders != 1 || `$notes != 1) { exit(61); }
`$db->close();
"@

$tableOutput = & $PhpExe -r $sqlTables 2>&1
$tableExit = $LASTEXITCODE
$tableOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }

if ($tableExit -ne 0) {
    Fail "Tabel folders/notes belum tersedia."
}

Ok "Tabel folders dan notes tersedia"

Step "7. RUN SEEDER"

Push-Location $ProjectRoot
try {
    & $PhpExe spark db:seed BrowserNoteSeeder
    if ($LASTEXITCODE -ne 0) {
        Fail "Seeder gagal."
    }
}
finally {
    Pop-Location
}

Ok "Seeder PASS"

Step "8. VERIFY SEEDED DATA"

$sqlSeed = @"
`$db = new SQLite3('$dbEscaped');
`$folders = `$db->querySingle("SELECT COUNT(*) FROM folders");
`$notes = `$db->querySingle("SELECT COUNT(*) FROM notes");
`$folderName = `$db->querySingle("SELECT name FROM folders ORDER BY id LIMIT 1");
`$noteTitle = `$db->querySingle("SELECT title FROM notes ORDER BY id LIMIT 1");
echo "folders=`$folders`nnotes=`$notes`nfirst_folder=`$folderName`nfirst_note=`$noteTitle`n";
if (`$folders < 1 || `$notes < 1) { exit(71); }
`$db->close();
"@

$seedOutput = & $PhpExe -r $sqlSeed 2>&1
$seedExit = $LASTEXITCODE
$seedOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }

if ($seedExit -ne 0) {
    Fail "Data awal tidak ditemukan."
}

Ok "Seed data terverifikasi"

Step "9. CRUD VERIFICATION"

$sqlCrud = @"
`$db = new SQLite3('$dbEscaped');
`$db->exec('PRAGMA foreign_keys = ON');
`$now = date('Y-m-d H:i:s');

`$stmt = `$db->prepare('INSERT INTO folders (name, sort_order, created_at, updated_at) VALUES (:name, 9999, :now, :now)');
`$stmt->bindValue(':name', '__STAGE02B_TEST__', SQLITE3_TEXT);
`$stmt->bindValue(':now', `$now, SQLITE3_TEXT);

`$result = `$stmt->execute();
if (!`$result) { exit(81); }

`$folderId = `$db->lastInsertRowID();

`$stmt = `$db->prepare('INSERT INTO notes (folder_id, title, content, content_text, is_archived, is_deleted, created_at, updated_at) VALUES (:folder_id, :title, :content, :text, 0, 0, :now, :now)');
`$stmt->bindValue(':folder_id', `$folderId, SQLITE3_INTEGER);
`$stmt->bindValue(':title', '__STAGE02B_NOTE__', SQLITE3_TEXT);
`$stmt->bindValue(':content', '<p>BrowserNote test</p>', SQLITE3_TEXT);
`$stmt->bindValue(':text', 'BrowserNote test', SQLITE3_TEXT);
`$stmt->bindValue(':now', `$now, SQLITE3_TEXT);

`$result2 = `$stmt->execute();
if (!`$result2) { exit(82); }

`$noteId = `$db->lastInsertRowID();

`$read = `$db->querySingle('SELECT title FROM notes WHERE id=' . (int)`$noteId);
if (`$read !== '__STAGE02B_NOTE__') { exit(83); }

if (!`$db->exec("UPDATE notes SET title='__STAGE02B_NOTE_UPDATED__' WHERE id=" . (int)`$noteId)) {
    exit(84);
}

`$updated = `$db->querySingle('SELECT title FROM notes WHERE id=' . (int)`$noteId);
if (`$updated !== '__STAGE02B_NOTE_UPDATED__') { exit(85); }

`$db->exec('DELETE FROM notes WHERE id=' . (int)`$noteId);
`$db->exec('DELETE FROM folders WHERE id=' . (int)`$folderId);

echo "CRUD_PASS`n";
`$db->close();
"@

$crudOutput = & $PhpExe -r $sqlCrud 2>&1
$crudExit = $LASTEXITCODE
$crudOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }

if ($crudExit -ne 0) {
    Fail "CRUD verification gagal."
}

Ok "CREATE / READ / UPDATE / DELETE PASS"

Step "10. FINAL CHECK"

$fileInfo = Get-Item $DbFile
Ok "Database size: $($fileInfo.Length) bytes"
Ok "Database: $DbFile"

Step "STAGE 02B PASS - STAGE 02 COMPLETE"

Write-Host ""
Write-Host "Project    : $ProjectRoot" -ForegroundColor White
Write-Host "Database   : $DbFile" -ForegroundColor White
Write-Host "Encoding   : PHP UTF-8 without BOM" -ForegroundColor White
Write-Host "Tables     : folders, notes" -ForegroundColor White
Write-Host "Migration  : PASS" -ForegroundColor White
Write-Host "Seeder     : PASS" -ForegroundColor White
Write-Host "CRUD       : PASS" -ForegroundColor White
Write-Host ""
Write-Host "STAGE 02 SELESAI" -ForegroundColor Green
Write-Host "Berikutnya : Stage 03 - Notes API" -ForegroundColor Green
