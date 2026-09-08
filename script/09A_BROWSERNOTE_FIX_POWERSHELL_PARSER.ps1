#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 09A
# FIX POWERSHELL 5.1 PARSER + RESUME STAGE 09
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$Stage09     = Join-Path $ProjectRoot 'script\09_BROWSERNOTE_SEARCH.ps1'
$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage09a_$Stamp"

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

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path $Stage09)) {
    Fail "Stage 09 tidak ditemukan: $Stage09"
}

Ok "Project ditemukan"
Ok "Stage 09 ditemukan"

Step "2. BACKUP BROKEN STAGE 09"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Copy-Item $Stage09 (Join-Path $BackupDir '09_BROWSERNOTE_SEARCH_BROKEN.ps1') -Force

Ok "Backup dibuat: $BackupDir"

Step "3. PATCH POWERSHELL 5.1 SYNTAX"

$content = [System.IO.File]::ReadAllText($Stage09)

# Fix 1 - multiline string concatenation inside function argument.
$patternCss = '(?s)Write-Utf8NoBom -Path \$CssPath -Content \(\s*\$cssExisting\.TrimEnd\(\)\s*\+\s*"`r`n"\s*\+\s*\$searchCss\.Trim\(\)\s*\+\s*"`r`n"\s*\)'

$replaceCss = '$combinedCss = $cssExisting.TrimEnd() + "`r`n" + $searchCss.Trim() + "`r`n"' + "`r`n" +
              'Write-Utf8NoBom -Path $CssPath -Content $combinedCss'

$newContent = [regex]::Replace(
    $content,
    $patternCss,
    $replaceCss,
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if ($newContent -eq $content) {
    Fail "Patch CSS concatenation tidak menemukan pola target."
}

$content = $newContent
Ok "Fix 1 PASS - CSS concatenation"

# Fix 2 - multiline IF operator.
$patternIf = '(?s)if\s*\(\s*\$archiveHit\.Count\s+-lt\s+1\s*-or\s+\[int\]\$archiveHit\[0\]\.is_archived\s+-ne\s+1\s*\)\s*\{'

$replaceIf = 'if ($archiveHit.Count -lt 1 -or [int]$archiveHit[0].is_archived -ne 1) {'

$newContent = [regex]::Replace(
    $content,
    $patternIf,
    $replaceIf,
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if ($newContent -eq $content) {
    Fail "Patch IF archive verification tidak menemukan pola target."
}

$content = $newContent
Ok "Fix 2 PASS - IF archive verification"

# Always write script as UTF-8 without BOM.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Stage09, $content, $utf8NoBom)

Ok "Stage 09 ditulis ulang UTF-8 without BOM"

Step "4. POWERSHELL PARSER VALIDATION"

$tokens = $null
$errors = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    $Stage09,
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count -gt 0) {
    Write-Host ""
    foreach ($errorItem in $errors) {
        Write-Host (
            "[PARSE] Line {0}, Col {1}: {2}" -f
            $errorItem.Extent.StartLineNumber,
            $errorItem.Extent.StartColumnNumber,
            $errorItem.Message
        ) -ForegroundColor Red
    }

    Fail "Stage 09 masih memiliki parser error. Tidak dijalankan."
}

Ok "PowerShell parser PASS - 0 errors"

Step "5. VERIFY PATCH MARKERS"

$verify = [System.IO.File]::ReadAllText($Stage09)

if (-not $verify.Contains('$combinedCss = $cssExisting.TrimEnd() + "`r`n" + $searchCss.Trim() + "`r`n"')) {
    Fail "Marker fix CSS tidak ditemukan."
}

if (-not $verify.Contains('if ($archiveHit.Count -lt 1 -or [int]$archiveHit[0].is_archived -ne 1) {')) {
    Fail "Marker fix IF tidak ditemukan."
}

Ok "Patch markers terverifikasi"

Step "6. RESUME STAGE 09"

Write-Host ""
Write-Host "Stage 09 akan dijalankan sekarang." -ForegroundColor White
Write-Host "Parser sudah PASS sebelum eksekusi." -ForegroundColor White
Write-Host ""

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Stage09

$childExit = $LASTEXITCODE

if ($childExit -ne 0) {
    Fail "Stage 09 masih gagal pada runtime. Exit code: $childExit"
}

Step "STAGE 09A PASS"

Write-Host ""
Write-Host "PowerShell parser : PASS" -ForegroundColor White
Write-Host "Stage 09          : PASS" -ForegroundColor White
Write-Host ""
Write-Host "Buka:" -ForegroundColor Cyan
Write-Host "http://localhost/browsernote/public/" -ForegroundColor Cyan
