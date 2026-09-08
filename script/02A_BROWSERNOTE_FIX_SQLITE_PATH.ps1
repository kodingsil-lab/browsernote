#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 02A
# FIX SQLITE PATH + RESUME STAGE 02
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$EnvFile     = Join-Path $ProjectRoot '.env'
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

function Set-EnvValue {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Value
    )

    $content = Get-Content $Path -Raw
    $escapedKey = [regex]::Escape($Key)
    $pattern = "(?m)^\s*#?\s*$escapedKey\s*=.*$"
    $newLine = "$Key = $Value"

    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $newLine, 1)
    } else {
        $content = $content.TrimEnd() + "`r`n$newLine`r`n"
    }

    Set-Content -Path $Path -Value $content -Encoding UTF8
}

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path (Join-Path $ProjectRoot 'spark'))) {
    Fail "spark tidak ditemukan."
}

if (-not (Test-Path $EnvFile)) {
    Fail ".env tidak ditemukan: $EnvFile"
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

Ok "Project ditemukan"
Ok "PHP ditemukan: $PhpExe"
Ok ".env ditemukan"

$modules = & $PhpExe -m
if ($modules -notcontains 'sqlite3') {
    Fail "Ekstensi PHP sqlite3 belum aktif."
}
Ok "SQLite3 aktif"

Step "2. BACKUP .ENV"

$backupDir = Join-Path $ProjectRoot 'writable\backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$envBackup = Join-Path $backupDir ".env_before_sqlite_fix_$stamp"

Copy-Item $EnvFile $envBackup -Force
Ok "Backup .env dibuat: $envBackup"

Step "3. FIX SQLITE CONFIGURATION"

# Untuk SQLite3 CI4, nama file tanpa separator otomatis diletakkan di WRITEPATH.
Set-EnvValue -Path $EnvFile -Key 'database.default.database' -Value 'browsernote.sqlite'
Set-EnvValue -Path $EnvFile -Key 'database.default.DBDriver' -Value 'SQLite3'
Set-EnvValue -Path $EnvFile -Key 'database.default.foreignKeys' -Value 'true'
Set-EnvValue -Path $EnvFile -Key 'database.default.busyTimeout' -Value '5000'

Ok "database.default.database = browsernote.sqlite"
Ok "database.default.DBDriver = SQLite3"
Ok "foreignKeys = true"
Ok "busyTimeout = 5000"

Step "4. ENSURE WRITABLE DATABASE FILE"

$writable = Join-Path $ProjectRoot 'writable'
if (-not (Test-Path $writable)) {
    New-Item -ItemType Directory -Path $writable -Force | Out-Null
}

if (-not (Test-Path $DbFile)) {
    New-Item -ItemType File -Path $DbFile -Force | Out-Null
    Ok "Database dibuat: $DbFile"
} else {
    Ok "Database tersedia: $DbFile"
}

# Tes akses langsung PHP SQLite3.
$dbEscaped = $DbFile.Replace('\', '\\').Replace("'", "\'")
$directTest = "`$db = new SQLite3('$dbEscaped'); echo `$db->querySingle('SELECT 1'); `$db->close();"

$directOutput = & $PhpExe -r $directTest 2>&1
if ($LASTEXITCODE -ne 0 -or (($directOutput -join '') -notmatch '1')) {
    Write-Host $directOutput
    Fail "PHP CLI tidak dapat membuka file SQLite secara langsung."
}

Ok "PHP CLI dapat membuka SQLite"

Step "5. RUN MIGRATIONS AGAIN"

Push-Location $ProjectRoot
try {
    & $PhpExe spark migrate
    if ($LASTEXITCODE -ne 0) {
        Fail "Migration gagal setelah perbaikan SQLite."
    }
}
finally {
    Pop-Location
}

Ok "Migration PASS"

Step "6. VERIFY MIGRATED TABLES BEFORE SEED"

$sqlTables = @"
`$db = new SQLite3('$dbEscaped');
`$folders = `$db->querySingle("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='folders'");
`$notes   = `$db->querySingle("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='notes'");
`$mig     = `$db->querySingle("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='migrations'");
echo "folders=`$folders`nnotes=`$notes`nmigrations=`$mig`n";
if (`$folders != 1 || `$notes != 1) { exit(61); }
`$db->close();
"@

$tableOutput = & $PhpExe -r $sqlTables 2>&1
$tableExit = $LASTEXITCODE
$tableOutput | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }

if ($tableExit -ne 0) {
    Fail "Tabel folders/notes belum terbentuk."
}

Ok "Tabel folders dan notes tersedia"

Step "7. RUN SEEDER"

Push-Location $ProjectRoot
try {
    & $PhpExe spark db:seed BrowserNoteSeeder
    if ($LASTEXITCODE -ne 0) {
        Fail "Seeder masih gagal."
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

Ok "Data awal terverifikasi"

Step "9. CRUD VERIFICATION"

$sqlCrud = @"
`$db = new SQLite3('$dbEscaped');
`$db->exec('PRAGMA foreign_keys = ON');
`$now = date('Y-m-d H:i:s');

`$stmt = `$db->prepare('INSERT INTO folders (name, sort_order, created_at, updated_at) VALUES (:name, 9999, :now, :now)');
`$stmt->bindValue(':name', '__STAGE02A_TEST__', SQLITE3_TEXT);
`$stmt->bindValue(':now', `$now, SQLITE3_TEXT);
if (!`$stmt->execute()) { exit(81); }
`$folderId = `$db->lastInsertRowID();

`$stmt = `$db->prepare('INSERT INTO notes (folder_id, title, content, content_text, is_archived, is_deleted, created_at, updated_at) VALUES (:folder_id, :title, :content, :text, 0, 0, :now, :now)');
`$stmt->bindValue(':folder_id', `$folderId, SQLITE3_INTEGER);
`$stmt->bindValue(':title', '__STAGE02A_NOTE__', SQLITE3_TEXT);
`$stmt->bindValue(':content', '<p>BrowserNote test</p>', SQLITE3_TEXT);
`$stmt->bindValue(':text', 'BrowserNote test', SQLITE3_TEXT);
`$stmt->bindValue(':now', `$now, SQLITE3_TEXT);
if (!`$stmt->execute()) { exit(82); }
`$noteId = `$db->lastInsertRowID();

`$read = `$db->querySingle('SELECT title FROM notes WHERE id=' . (int)`$noteId);
if (`$read !== '__STAGE02A_NOTE__') { exit(83); }

if (!`$db->exec("UPDATE notes SET title='__STAGE02A_NOTE_UPDATED__' WHERE id=" . (int)`$noteId)) { exit(84); }

`$updated = `$db->querySingle('SELECT title FROM notes WHERE id=' . (int)`$noteId);
if (`$updated !== '__STAGE02A_NOTE_UPDATED__') { exit(85); }

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

Step "10. FINAL DATABASE INFO"

$fileInfo = Get-Item $DbFile
Ok "SQLite size: $($fileInfo.Length) bytes"
Ok "SQLite location: $DbFile"

Step "STAGE 02A PASS - STAGE 02 RECOVERED"

Write-Host ""
Write-Host "Project    : $ProjectRoot" -ForegroundColor White
Write-Host "Database   : $DbFile" -ForegroundColor White
Write-Host "Driver     : SQLite3" -ForegroundColor White
Write-Host "Tables     : folders, notes" -ForegroundColor White
Write-Host "Seed       : PASS" -ForegroundColor White
Write-Host "CRUD       : PASS" -ForegroundColor White
Write-Host ""
Write-Host "STAGE 02 SELESAI" -ForegroundColor Green
Write-Host "Berikutnya : Stage 03 - Notes API" -ForegroundColor Green
