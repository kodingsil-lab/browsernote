#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 09B
# FIX SEARCH UI MARKER + RESUME STAGE 09
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$Stage09     = Join-Path $ProjectRoot 'script\09_BROWSERNOTE_SEARCH.ps1'
$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage09b_$Stamp"

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

Step "2. BACKUP STAGE 09"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Copy-Item $Stage09 (Join-Path $BackupDir '09_BROWSERNOTE_SEARCH_before_09B.ps1') -Force

Ok "Backup dibuat: $BackupDir"

Step "3. PATCH SEARCH UI LOGIC"

$content = [System.IO.File]::ReadAllText($Stage09)

$startText = '$oldSearch = @'''
$endText   = 'Write-Utf8NoBom -Path $ViewPath -Content $viewText'

$startIndex = $content.IndexOf($startText)
if ($startIndex -lt 0) {
    Fail "Awal blok search UI lama tidak ditemukan."
}

$endIndex = $content.IndexOf($endText, $startIndex)
if ($endIndex -lt 0) {
    Fail "Akhir blok search UI lama tidak ditemukan."
}

$endIndex = $endIndex + $endText.Length

$replacement = @'
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

if ($viewText.Contains('id="searchInput"')) {
    Ok "Search UI sudah aktif, patch HTML dilewati."
}
else {
    $searchPattern = '(?s)<label\s+class="search-box[^"]*"[^>]*>.*?</label>'

    $match = [regex]::Match(
        $viewText,
        $searchPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $match.Success) {
        Fail "Elemen search-box tidak ditemukan pada view."
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

    Ok "Search box lama ditemukan dan diganti secara toleran."
}

Write-Utf8NoBom -Path $ViewPath -Content $viewText
'@

$replacement = $replacement.Replace("`n", "`r`n")

$content = $content.Substring(0, $startIndex) +
           $replacement +
           $content.Substring($endIndex)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Stage09, $content, $utf8NoBom)

Ok "Logic search UI Stage 09 diperbaiki"

Step "4. POWERSHELL PARSER VALIDATION"

$tokens = $null
$errors = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    $Stage09,
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count -gt 0) {
    foreach ($errorItem in $errors) {
        Write-Host (
            "[PARSE] Line {0}, Col {1}: {2}" -f
            $errorItem.Extent.StartLineNumber,
            $errorItem.Extent.StartColumnNumber,
            $errorItem.Message
        ) -ForegroundColor Red
    }

    Fail "Stage 09 masih memiliki parser error."
}

Ok "PowerShell parser PASS - 0 errors"

Step "5. VERIFY PATCH"

$verify = [System.IO.File]::ReadAllText($Stage09)

if (-not $verify.Contains('$searchPattern = ''(?s)<label\s+class="search-box[^"]*"[^>]*>.*?</label>''')) {
    Fail "Marker regex search-box tidak ditemukan."
}

if (-not $verify.Contains('Search box lama ditemukan dan diganti secara toleran.')) {
    Fail "Marker tolerant UI patch tidak ditemukan."
}

Ok "Tolerant search UI patch terverifikasi"

Step "6. RESUME STAGE 09"

Write-Host ""
Write-Host "Stage 09 akan dijalankan ulang." -ForegroundColor White
Write-Host "SearchApi dan route yang sudah dibuat sebelumnya aman karena patch bersifat idempotent." -ForegroundColor White
Write-Host ""

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Stage09

$childExit = $LASTEXITCODE

if ($childExit -ne 0) {
    Fail "Stage 09 masih gagal pada runtime. Exit code: $childExit"
}

Step "STAGE 09B PASS"

Write-Host ""
Write-Host "PowerShell parser : PASS" -ForegroundColor White
Write-Host "Search UI patch   : PASS" -ForegroundColor White
Write-Host "Stage 09          : PASS" -ForegroundColor White
Write-Host ""
Write-Host "Buka:" -ForegroundColor Cyan
Write-Host "http://localhost/browsernote/public/" -ForegroundColor Cyan
