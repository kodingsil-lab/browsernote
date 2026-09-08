#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 02C
# RESUME AFTER MIGRATION + ROBUST VERIFY
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$DbFile      = Join-Path $ProjectRoot 'writable\browsernote.sqlite'
$TempDir     = Join-Path $ProjectRoot 'writable\stage02c_temp'

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

function Run-PHPFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$FailMessage
    )

    $output = & $script:PhpExe $Path 2>&1
    $exitCode = $LASTEXITCODE

    $output | ForEach-Object {
        Write-Host $_ -ForegroundColor DarkGray
    }

    if ($exitCode -ne 0) {
        Fail $FailMessage
    }
}

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "spark tidak ditemukan."
}

$script:PhpExe = Resolve-PHP
if (-not $script:PhpExe) {
    Fail "PHP tidak ditemukan."
}

if (-not (Test-Path $DbFile)) {
    Fail "Database SQLite tidak ditemukan: $DbFile"
}

$modules = & $script:PhpExe -m
if ($modules -notcontains 'sqlite3') {
    Fail "Ekstensi sqlite3 belum aktif."
}

Ok "Project ditemukan"
Ok "PHP ditemukan: $script:PhpExe"
Ok "SQLite3 aktif"
Ok "Database ditemukan: $DbFile"

Step "2. PREPARE TEMP VERIFY FILES"

if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Ok "Folder verifikasi sementara dibuat"

$dbPhp = $DbFile.Replace('\', '/').Replace("'", "\'")

Step "3. VERIFY MIGRATION STATE"

$verifyTablesPath = Join-Path $TempDir 'verify_tables.php'

$verifyTablesPhp = @"
<?php

`$db = new SQLite3('$dbPhp');

function tableExists(SQLite3 `$db, string `$name): bool
{
    `$stmt = `$db->prepare("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = :name");
    `$stmt->bindValue(':name', `$name, SQLITE3_TEXT);
    return (int) `$stmt->execute()->fetchArray(SQLITE3_NUM)[0] === 1;
}

`$required = ['migrations', 'folders', 'notes'];

foreach (`$required as `$table) {
    if (!tableExists(`$db, `$table)) {
        fwrite(STDERR, "MISSING_TABLE=`$table\n");
        exit(31);
    }
}

`$folderCount = (int) `$db->querySingle('SELECT COUNT(*) FROM folders');
`$noteCount   = (int) `$db->querySingle('SELECT COUNT(*) FROM notes');

echo "TABLES_PASS\n";
echo "folders=`$folderCount\n";
echo "notes=`$noteCount\n";

`$db->close();
"@

Write-Utf8NoBom -Path $verifyTablesPath -Content $verifyTablesPhp
Run-PHPFile -Path $verifyTablesPath -FailMessage "Verifikasi tabel hasil migration gagal."
Ok "Migration state terverifikasi"

Step "4. RUN MIGRATE SAFELY"

Push-Location $ProjectRoot
try {
    & $script:PhpExe spark migrate
    if ($LASTEXITCODE -ne 0) {
        Fail "php spark migrate gagal."
    }
}
finally {
    Pop-Location
}

Ok "Tidak ada migration bermasalah"

Step "5. RUN SEEDER"

$SeederFile = Join-Path $ProjectRoot 'app\Database\Seeds\BrowserNoteSeeder.php'

if (-not (Test-Path $SeederFile)) {
    Fail "BrowserNoteSeeder.php tidak ditemukan."
}

$lint = & $script:PhpExe -l $SeederFile 2>&1
if ($LASTEXITCODE -ne 0) {
    $lint | ForEach-Object { Write-Host $_ }
    Fail "Syntax BrowserNoteSeeder.php tidak valid."
}

Ok "Seeder syntax valid"

Push-Location $ProjectRoot
try {
    & $script:PhpExe spark db:seed BrowserNoteSeeder
    if ($LASTEXITCODE -ne 0) {
        Fail "Seeder gagal."
    }
}
finally {
    Pop-Location
}

Ok "Seeder PASS"

Step "6. VERIFY SEEDED DATA"

$verifySeedPath = Join-Path $TempDir 'verify_seed.php'

$verifySeedPhp = @"
<?php

`$db = new SQLite3('$dbPhp');

`$folderCount = (int) `$db->querySingle('SELECT COUNT(*) FROM folders');
`$noteCount   = (int) `$db->querySingle('SELECT COUNT(*) FROM notes');

if (`$folderCount < 1) {
    fwrite(STDERR, "NO_FOLDER\n");
    exit(41);
}

if (`$noteCount < 1) {
    fwrite(STDERR, "NO_NOTE\n");
    exit(42);
}

`$folderName = (string) `$db->querySingle('SELECT name FROM folders ORDER BY id ASC LIMIT 1');
`$noteTitle  = (string) `$db->querySingle('SELECT title FROM notes ORDER BY id ASC LIMIT 1');

echo "SEED_PASS\n";
echo "folders=`$folderCount\n";
echo "notes=`$noteCount\n";
echo "first_folder=`$folderName\n";
echo "first_note=`$noteTitle\n";

`$db->close();
"@

Write-Utf8NoBom -Path $verifySeedPath -Content $verifySeedPhp
Run-PHPFile -Path $verifySeedPath -FailMessage "Data seeder tidak terverifikasi."
Ok "Data awal terverifikasi"

Step "7. CRUD VERIFICATION"

$verifyCrudPath = Join-Path $TempDir 'verify_crud.php'

$verifyCrudPhp = @"
<?php

`$db = new SQLite3('$dbPhp');
`$db->exec('PRAGMA foreign_keys = ON');
`$db->busyTimeout(5000);

`$now = date('Y-m-d H:i:s');
`$folderId = null;
`$noteId = null;

try {
    `$db->exec('BEGIN');

    `$stmt = `$db->prepare(
        'INSERT INTO folders (name, sort_order, created_at, updated_at)
         VALUES (:name, :sort_order, :created_at, :updated_at)'
    );
    `$stmt->bindValue(':name', '__STAGE02C_TEST__', SQLITE3_TEXT);
    `$stmt->bindValue(':sort_order', 9999, SQLITE3_INTEGER);
    `$stmt->bindValue(':created_at', `$now, SQLITE3_TEXT);
    `$stmt->bindValue(':updated_at', `$now, SQLITE3_TEXT);

    if (!`$stmt->execute()) {
        throw new RuntimeException('CREATE_FOLDER_FAILED');
    }

    `$folderId = `$db->lastInsertRowID();

    `$stmt = `$db->prepare(
        'INSERT INTO notes
        (folder_id, title, content, content_text, is_archived, is_deleted, created_at, updated_at)
        VALUES
        (:folder_id, :title, :content, :content_text, 0, 0, :created_at, :updated_at)'
    );
    `$stmt->bindValue(':folder_id', `$folderId, SQLITE3_INTEGER);
    `$stmt->bindValue(':title', '__STAGE02C_NOTE__', SQLITE3_TEXT);
    `$stmt->bindValue(':content', '<p>BrowserNote CRUD test</p>', SQLITE3_TEXT);
    `$stmt->bindValue(':content_text', 'BrowserNote CRUD test', SQLITE3_TEXT);
    `$stmt->bindValue(':created_at', `$now, SQLITE3_TEXT);
    `$stmt->bindValue(':updated_at', `$now, SQLITE3_TEXT);

    if (!`$stmt->execute()) {
        throw new RuntimeException('CREATE_NOTE_FAILED');
    }

    `$noteId = `$db->lastInsertRowID();

    `$stmt = `$db->prepare('SELECT title FROM notes WHERE id = :id');
    `$stmt->bindValue(':id', `$noteId, SQLITE3_INTEGER);
    `$row = `$stmt->execute()->fetchArray(SQLITE3_ASSOC);

    if (!`$row || `$row['title'] !== '__STAGE02C_NOTE__') {
        throw new RuntimeException('READ_FAILED');
    }

    `$stmt = `$db->prepare('UPDATE notes SET title = :title, updated_at = :updated_at WHERE id = :id');
    `$stmt->bindValue(':title', '__STAGE02C_NOTE_UPDATED__', SQLITE3_TEXT);
    `$stmt->bindValue(':updated_at', `$now, SQLITE3_TEXT);
    `$stmt->bindValue(':id', `$noteId, SQLITE3_INTEGER);

    if (!`$stmt->execute()) {
        throw new RuntimeException('UPDATE_FAILED');
    }

    `$stmt = `$db->prepare('SELECT title FROM notes WHERE id = :id');
    `$stmt->bindValue(':id', `$noteId, SQLITE3_INTEGER);
    `$updated = `$stmt->execute()->fetchArray(SQLITE3_ASSOC);

    if (!`$updated || `$updated['title'] !== '__STAGE02C_NOTE_UPDATED__') {
        throw new RuntimeException('UPDATE_VERIFY_FAILED');
    }

    `$stmt = `$db->prepare('DELETE FROM notes WHERE id = :id');
    `$stmt->bindValue(':id', `$noteId, SQLITE3_INTEGER);

    if (!`$stmt->execute()) {
        throw new RuntimeException('DELETE_NOTE_FAILED');
    }

    `$stmt = `$db->prepare('DELETE FROM folders WHERE id = :id');
    `$stmt->bindValue(':id', `$folderId, SQLITE3_INTEGER);

    if (!`$stmt->execute()) {
        throw new RuntimeException('DELETE_FOLDER_FAILED');
    }

    `$remainingNote = (int) `$db->querySingle('SELECT COUNT(*) FROM notes WHERE id = ' . (int) `$noteId);
    `$remainingFolder = (int) `$db->querySingle('SELECT COUNT(*) FROM folders WHERE id = ' . (int) `$folderId);

    if (`$remainingNote !== 0 || `$remainingFolder !== 0) {
        throw new RuntimeException('DELETE_VERIFY_FAILED');
    }

    `$db->exec('COMMIT');

    echo "CREATE_PASS\n";
    echo "READ_PASS\n";
    echo "UPDATE_PASS\n";
    echo "DELETE_PASS\n";
    echo "CRUD_PASS\n";
}
catch (Throwable `$e) {
    `$db->exec('ROLLBACK');

    if (`$noteId !== null) {
        `$db->exec('DELETE FROM notes WHERE id = ' . (int) `$noteId);
    }

    if (`$folderId !== null) {
        `$db->exec('DELETE FROM folders WHERE id = ' . (int) `$folderId);
    }

    fwrite(STDERR, `$e->getMessage() . "\n");
    exit(51);
}

`$db->close();
"@

Write-Utf8NoBom -Path $verifyCrudPath -Content $verifyCrudPhp
Run-PHPFile -Path $verifyCrudPath -FailMessage "CRUD verification gagal."
Ok "CREATE / READ / UPDATE / DELETE PASS"

Step "8. VERIFY MODEL SYNTAX"

$ModelFiles = @(
    (Join-Path $ProjectRoot 'app\Models\FolderModel.php'),
    (Join-Path $ProjectRoot 'app\Models\NoteModel.php')
)

foreach ($file in $ModelFiles) {
    if (-not (Test-Path $file)) {
        Fail "Model tidak ditemukan: $file"
    }

    $lint = & $script:PhpExe -l $file 2>&1

    if ($LASTEXITCODE -ne 0) {
        $lint | ForEach-Object { Write-Host $_ }
        Fail "PHP lint gagal: $file"
    }

    Ok "Model valid: $(Split-Path $file -Leaf)"
}

Step "9. CLEAN TEMP FILES"

Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Ok "File verifikasi sementara dibersihkan"

Step "STAGE 02C PASS - STAGE 02 COMPLETE"

Write-Host ""
Write-Host "Project    : $ProjectRoot" -ForegroundColor White
Write-Host "Database   : $DbFile" -ForegroundColor White
Write-Host "Tables     : folders, notes" -ForegroundColor White
Write-Host "Migration  : PASS" -ForegroundColor White
Write-Host "Seeder     : PASS" -ForegroundColor White
Write-Host "CRUD       : PASS" -ForegroundColor White
Write-Host "Models     : PASS" -ForegroundColor White
Write-Host ""
Write-Host "STAGE 02 SELESAI" -ForegroundColor Green
Write-Host "Berikutnya : Stage 03 - Notes API" -ForegroundColor Green
