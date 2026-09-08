#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 04A
# PATCH TINYMCE VERSION TO 8.9.0 + RESUME STAGE 04
# Project : C:\xampp\htdocs\browsernote
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$Stage04     = Join-Path $ProjectRoot 'script\04_BROWSERNOTE_TINYMCE_EDITOR.ps1'
$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage04a_$Stamp"

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

if (-not (Test-Path $Stage04)) {
    Fail "Script Stage 04 tidak ditemukan: $Stage04"
}

Ok "Project ditemukan"
Ok "Stage 04 ditemukan"

Step "2. BACKUP STAGE 04 SCRIPT"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Copy-Item $Stage04 (Join-Path $BackupDir '04_BROWSERNOTE_TINYMCE_EDITOR.ps1') -Force

Ok "Backup dibuat: $BackupDir"

Step "3. PATCH TINYMCE CONSTRAINT"

$content = [System.IO.File]::ReadAllText($Stage04)

$oldA = "'tinymce/tinymce:^8.0'"
$oldB = '"tinymce/tinymce:^8.0"'
$new  = "'tinymce/tinymce:8.9.0'"

if ($content.Contains($oldA)) {
    $content = $content.Replace($oldA, $new)
}
elseif ($content.Contains($oldB)) {
    $content = $content.Replace($oldB, $new)
}
elseif ($content.Contains("'tinymce/tinymce:8.9.0'")) {
    Ok "Stage 04 sudah memakai TinyMCE 8.9.0"
}
else {
    Fail "Constraint TinyMCE lama tidak ditemukan di Stage 04."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Stage04, $content, $utf8NoBom)

$verify = [System.IO.File]::ReadAllText($Stage04)

if (-not $verify.Contains("'tinymce/tinymce:8.9.0'")) {
    Fail "Patch versi TinyMCE gagal."
}

Ok "TinyMCE dikunci ke 8.9.0"

Step "4. RESUME STAGE 04"

Write-Host ""
Write-Host "Stage 04 akan dijalankan ulang dari awal." -ForegroundColor White
Write-Host "Composer sebelumnya sudah rollback, jadi aman." -ForegroundColor White
Write-Host ""

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Stage04

$childExit = $LASTEXITCODE

if ($childExit -ne 0) {
    Fail "Stage 04 masih gagal. Exit code: $childExit"
}

Step "STAGE 04A PASS"

Write-Host ""
Write-Host "TinyMCE version patch : 8.9.0" -ForegroundColor White
Write-Host "Stage 04             : PASS" -ForegroundColor White
Write-Host ""
Write-Host "Buka:" -ForegroundColor Cyan
Write-Host "http://localhost/browsernote/public/" -ForegroundColor Cyan
