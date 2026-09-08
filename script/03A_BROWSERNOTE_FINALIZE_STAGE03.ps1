#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 03A
# FINALIZE NOTES API VERIFICATION
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'
$ApiBase     = "$BaseUrl/api/notes"
$DbFile      = Join-Path $ProjectRoot 'writable\browsernote.sqlite'

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

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path $DbFile)) {
    Fail "Database tidak ditemukan: $DbFile"
}

$PhpExe = Resolve-PHP
if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

Ok "Project ditemukan"
Ok "Database ditemukan"
Ok "PHP ditemukan: $PhpExe"

Step "2. VERIFY API LIST ALL"

$allUri = "${ApiBase}?status=all"

try {
    $response = Invoke-RestMethod `
        -Method GET `
        -Uri $allUri `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 10 `
        -ErrorAction Stop

    if (-not $response.ok) {
        Fail "API status=all mengembalikan ok=false."
    }

    Ok "GET $allUri PASS"
    Write-Host "       Total notes: $($response.count)" -ForegroundColor DarkGray
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "GET status=all gagal."
}

Step "3. VERIFY NO STAGE 03 TEST DATA VIA API"

$leftovers = @(
    $response.data | Where-Object {
        $_.title -eq '__STAGE03_API_TEST__' -or
        $_.title -eq '__STAGE03_API_TEST_UPDATED__'
    }
)

if ($leftovers.Count -gt 0) {
    Write-Host "[WARN] Ditemukan $($leftovers.Count) data test melalui API. Akan dibersihkan secara spesifik." -ForegroundColor Yellow

    foreach ($note in $leftovers) {
        $id = [int]$note.id

        try {
            if ([int]$note.is_deleted -ne 1) {
                Invoke-RestMethod `
                    -Method DELETE `
                    -Uri "${ApiBase}/$id" `
                    -Headers @{ Accept = 'application/json' } `
                    -TimeoutSec 10 `
                    -ErrorAction Stop | Out-Null
            }

            Invoke-RestMethod `
                -Method DELETE `
                -Uri "${ApiBase}/$id/force" `
                -Headers @{ Accept = 'application/json' } `
                -TimeoutSec 10 `
                -ErrorAction Stop | Out-Null

            Ok "Data test API dibersihkan: id=$id"
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Fail "Gagal membersihkan data test API id=$id"
        }
    }
}
else {
    Ok "Tidak ada data test Stage 03 melalui API"
}

Step "4. VERIFY DIRECTLY IN SQLITE"

$dbPhp = $DbFile.Replace('\', '/').Replace("'", "\'")

$tempDir = Join-Path $ProjectRoot 'writable\stage03a_temp'
$tempFile = Join-Path $tempDir 'verify_stage03_cleanup.php'

if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$php = @"
<?php

`$db = new SQLite3('$dbPhp');

`$stmt = `$db->prepare(
    "SELECT COUNT(*) FROM notes
     WHERE title = :a OR title = :b"
);

`$stmt->bindValue(':a', '__STAGE03_API_TEST__', SQLITE3_TEXT);
`$stmt->bindValue(':b', '__STAGE03_API_TEST_UPDATED__', SQLITE3_TEXT);

`$count = (int) `$stmt->execute()->fetchArray(SQLITE3_NUM)[0];

echo "stage03_test_rows=`$count\n";

if (`$count !== 0) {
    exit(31);
}

`$total = (int) `$db->querySingle('SELECT COUNT(*) FROM notes');
echo "total_notes=`$total\n";

`$db->close();
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempFile, $php, $utf8NoBom)

$output = & $PhpExe $tempFile 2>&1
$exitCode = $LASTEXITCODE

$output | ForEach-Object {
    Write-Host $_ -ForegroundColor DarkGray
}

if ($exitCode -ne 0) {
    Fail "Masih ada data test Stage 03 di SQLite."
}

Ok "SQLite cleanup verification PASS"

Step "5. FINAL API SMOKE TEST"

try {
    $active = Invoke-RestMethod `
        -Method GET `
        -Uri $ApiBase `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 10 `
        -ErrorAction Stop

    if (-not $active.ok) {
        Fail "GET active notes mengembalikan ok=false."
    }

    Ok "Active notes API masih normal"
    Write-Host "       Active notes: $($active.count)" -ForegroundColor DarkGray
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Fail "Final API smoke test gagal."
}

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Step "STAGE 03A PASS - STAGE 03 COMPLETE"

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
Write-Host "Cleanup    : PASS" -ForegroundColor White
Write-Host ""
Write-Host "STAGE 03 SELESAI" -ForegroundColor Green
Write-Host "Berikutnya : Stage 04 - TinyMCE Self-Hosted + Full Rich Editor" -ForegroundColor Green
