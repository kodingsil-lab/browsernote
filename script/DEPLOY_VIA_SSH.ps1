#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9.-]+$')]
    [string]$SshHost,
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9_.-]+$')]
    [string]$SshUser,
    [ValidateRange(1, 65535)]
    [int]$SshPort = 22,
    [ValidateSet('check', 'install', 'update')]
    [string]$Action = 'check',
    [ValidatePattern('^[a-zA-Z0-9_.-]+$')]
    [string]$AuthUser = 'penulis',
    [string]$IdentityFile = '',
    [string]$PackagePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
foreach ($command in @('ssh.exe', 'scp.exe', 'tar.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Command tidak tersedia: $command" }
}
if ($IdentityFile) {
    $IdentityFile = (Resolve-Path -LiteralPath $IdentityFile).Path
    if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) { throw "SSH identity file tidak ditemukan: $IdentityFile" }
}
if (-not $PackagePath) {
    & (Join-Path $PSScriptRoot 'BUILD_DEPLOY_PACKAGE.ps1')
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Pembuatan paket gagal dengan exit code $LASTEXITCODE." }
    $PackagePath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build') -Filter 'browsernote-deploy-*.tar.gz' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
$PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw "Paket deploy tidak ditemukan: $PackagePath" }
$entries = & tar.exe -tzf $PackagePath
if ($LASTEXITCODE -ne 0) { throw 'Paket deploy tidak dapat dibaca.' }
$required = @('deploy-cpanel.sh', 'deploy/hosting.php', 'deploy/public.htaccess', 'composer.lock', 'public/index.php')
foreach ($requiredEntry in $required) {
    if ($entries -notcontains $requiredEntry) { throw "Paket deploy tidak lengkap: $requiredEntry" }
}
$forbidden = $entries | Where-Object { $_ -match '(^|/)(\.env|\.git|writable)(/|$)|\.sqlite(?:-|$)|^vendor/' }
if ($forbidden) { throw 'Paket memuat konfigurasi atau data lokal yang tidak boleh diunggah.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$remoteArchive = "browsernote-upload-$stamp.tar.gz"
$remoteSource = "browsernote-deploy-src-$stamp"
$remote = "$SshUser@$SshHost"
$sshOptions = @('-p', "$SshPort")
$scpOptions = @('-P', "$SshPort")
if ($IdentityFile) {
    $sshOptions += @('-i', $IdentityFile)
    $scpOptions += @('-i', $IdentityFile)
}
Write-Host "Mengunggah paket ke ${remote}:~/$remoteArchive" -ForegroundColor Cyan
& scp.exe @scpOptions -- $PackagePath "${remote}:~/$remoteArchive"
if ($LASTEXITCODE -ne 0) { throw "Upload SCP gagal dengan exit code $LASTEXITCODE." }
# Nilai yang disisipkan dibatasi ke huruf, angka, titik, dash, dan underscore.
# Password tetap dimasukkan secara interaktif oleh SSH/htpasswd.
$remoteCommand = "set -e; " +
    "mkdir `"`$HOME/$remoteSource`"; " +
    "tar -xzf `"`$HOME/$remoteArchive`" -C `"`$HOME/$remoteSource`"; " +
    "cd `"`$HOME/$remoteSource`"; " +
    "AUTH_USER='$AuthUser' bash deploy-cpanel.sh '$Action'"
Write-Host "Menjalankan deploy action '$Action' melalui SSH..." -ForegroundColor Cyan
& ssh.exe -t @sshOptions -- $remote $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "Deploy SSH gagal dengan exit code $LASTEXITCODE. Source hosting dipertahankan di ~/$remoteSource untuk pemeriksaan."
}
Write-Host "Selesai. Source hosting: ~/$remoteSource" -ForegroundColor Green
if ($Action -eq 'check') {
    Write-Host 'Preflight lulus. Jalankan ulang dengan -Action install untuk pemasangan pertama.' -ForegroundColor Green
}
