[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $projectRoot 'build'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$archivePath = Join-Path $outputDir ('browsernote-deploy-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.tar.gz')
$files = @('app', 'public', 'deploy', 'composer.json', 'composer.lock', 'spark', 'deploy-cpanel.sh', '.env.hosting.example', 'DEPLOY_SSH.md', 'LICENSE')
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $file))) { throw "Berkas tidak tersedia: $file" }
}
& tar -czf $archivePath --exclude=.env '--exclude=*.sqlite*' '--exclude=*.log' -C $projectRoot @files
if ($LASTEXITCODE -ne 0) { throw 'Pembuatan paket deploy gagal.' }
Write-Host "Paket siap: $archivePath"
Write-Host 'Paket berisi kode dari workspace saat ini. Database catatan, konfigurasi lokal, dan vendor Composer tidak disertakan.'
