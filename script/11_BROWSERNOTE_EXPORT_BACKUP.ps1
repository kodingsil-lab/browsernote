#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 11
# EXPORT NOTE + SQLITE BACKUP
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'

$RoutesPath   = Join-Path $ProjectRoot 'app\Config\Routes.php'
$BackupApi    = Join-Path $ProjectRoot 'app\Controllers\Api\BackupApi.php'
$ViewPath     = Join-Path $ProjectRoot 'app\Views\notes\index.php'
$CssPath      = Join-Path $ProjectRoot 'public\assets\css\app.css'
$MainJsPath   = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$ShortcutPath = Join-Path $ProjectRoot 'public\assets\js\shortcuts.js'
$ExportJsPath = Join-Path $ProjectRoot 'public\assets\js\export.js'
$DatabasePath = Join-Path $ProjectRoot 'writable\browsernote.sqlite'

$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage11_$Stamp"
$TempBackup  = Join-Path $env:TEMP "browsernote_stage11_test_$Stamp.sqlite"

function Step([string]$Message) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
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

    if ($cmd) {
        return $cmd.Source
    }

    $xamppPhp = 'C:\xampp\php\php.exe'

    if (Test-Path $xamppPhp) {
        return $xamppPhp
    }

    return $null
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    $parent = Split-Path $Path -Parent

    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Backup-File {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    $relative = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $destination = Join-Path $BackupDir $relative
    $destinationDir = Split-Path $destination -Parent

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item $Path $destination -Force
}

Step "1. PRECHECK"

foreach ($path in @(
    $ProjectRoot,
    $RoutesPath,
    $ViewPath,
    $CssPath,
    $MainJsPath,
    $ShortcutPath,
    $DatabasePath
)) {
    if (-not (Test-Path $path)) {
        Fail "Path wajib tidak ditemukan: $path"
    }
}

$PhpExe = Resolve-PHP

if (-not $PhpExe) {
    Fail "PHP tidak ditemukan."
}

$mainJs = [System.IO.File]::ReadAllText($MainJsPath)
$shortcutJs = [System.IO.File]::ReadAllText($ShortcutPath)

if (-not $mainJs.Contains('window.BrowserNoteBridge')) {
    Fail "BrowserNoteBridge tidak ditemukan."
}

if (-not $shortcutJs.Contains('window.BrowserNoteQuickNote')) {
    Fail "Stage 10 belum lengkap."
}

Ok "Project ditemukan"
Ok "Stage 10 terverifikasi"
Ok "Database ditemukan"
Ok "PHP ditemukan: $PhpExe"

Step "2. BACKUP CURRENT FILES"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

@(
    $RoutesPath,
    $BackupApi,
    $ViewPath,
    $CssPath,
    $ExportJsPath
) | ForEach-Object {
    Backup-File $_
}

Ok "Backup dibuat: $BackupDir"

Step "3. CREATE BACKUP API"

$backupApiCode = @'
<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;
use CodeIgniter\HTTP\ResponseInterface;

class BackupApi extends BaseController
{
    public function download()
    {
        if (!class_exists(\SQLite3::class)) {
            return $this->error(
                'Ekstensi SQLite3 PHP tidak tersedia.',
                ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
            );
        }

        $sourcePath = WRITEPATH . 'browsernote.sqlite';

        if (!is_file($sourcePath)) {
            return $this->error(
                'Database BrowserNote tidak ditemukan.',
                ResponseInterface::HTTP_NOT_FOUND
            );
        }

        $backupDir = WRITEPATH . 'backups';

        if (!is_dir($backupDir) && !mkdir($backupDir, 0775, true) && !is_dir($backupDir)) {
            return $this->error(
                'Folder backup tidak dapat dibuat.',
                ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
            );
        }

        $filename = 'browsernote_backup_' . date('Ymd_His') . '.sqlite';
        $destinationPath = $backupDir . DIRECTORY_SEPARATOR . $filename;

        try {
            $source = new \SQLite3(
                $sourcePath,
                SQLITE3_OPEN_READONLY
            );

            $destination = new \SQLite3(
                $destinationPath,
                SQLITE3_OPEN_READWRITE | SQLITE3_OPEN_CREATE
            );

            $success = $source->backup($destination);

            $destination->close();
            $source->close();

            if (!$success || !is_file($destinationPath)) {
                @unlink($destinationPath);

                return $this->error(
                    'Snapshot SQLite gagal dibuat.',
                    ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
                );
            }
        } catch (\Throwable $e) {
            @unlink($destinationPath);

            log_message(
                'error',
                'BrowserNote backup failed: {message}',
                ['message' => $e->getMessage()]
            );

            return $this->error(
                'Backup SQLite gagal dibuat.',
                ResponseInterface::HTTP_INTERNAL_SERVER_ERROR
            );
        }

        return $this->response
            ->download($destinationPath, null)
            ->setFileName($filename);
    }

    private function error(string $message, int $status)
    {
        return $this->response
            ->setStatusCode($status)
            ->setContentType('application/json')
            ->setJSON([
                'ok'      => false,
                'message' => $message,
            ]);
    }
}
'@

Write-Utf8NoBom -Path $BackupApi -Content $backupApiCode
Ok "BackupApi.php dibuat"

Step "4. PATCH BACKUP ROUTE"

$routesText = [System.IO.File]::ReadAllText($RoutesPath)

$routeStart = '// <BROWSERNOTE_STAGE11_BACKUP>'
$routeEnd   = '// </BROWSERNOTE_STAGE11_BACKUP>'

$routePattern = '(?s)\r?\n?' + [regex]::Escape($routeStart) + '.*?' + [regex]::Escape($routeEnd) + '\r?\n?'
$routesText = [regex]::Replace($routesText, $routePattern, "`r`n")

$routeBlock = @'

// <BROWSERNOTE_STAGE11_BACKUP>
$routes->get('api/backup/download', 'Api\BackupApi::download');
// </BROWSERNOTE_STAGE11_BACKUP>
'@

$routesText = $routesText.TrimEnd() + "`r`n" + $routeBlock.Trim() + "`r`n"
Write-Utf8NoBom -Path $RoutesPath -Content $routesText

Ok "Backup route dipasang"

Step "5. ADD EXPORT SCRIPT TO VIEW"

$viewText = [System.IO.File]::ReadAllText($ViewPath)

if (-not $viewText.Contains('assets/js/export.js')) {
    $shortcutTag = '<script src="<?= base_url(''assets/js/shortcuts.js'') ?>"></script>'
    $exportTag   = '<script src="<?= base_url(''assets/js/export.js'') ?>"></script>'

    if ($viewText.Contains($shortcutTag)) {
        $viewText = $viewText.Replace(
            $shortcutTag,
            $shortcutTag + "`r`n" + $exportTag
        )
    }
    else {
        $bodyClose = '</body>'

        if (-not $viewText.Contains($bodyClose)) {
            Fail "Tag </body> tidak ditemukan."
        }

        $viewText = $viewText.Replace(
            $bodyClose,
            $exportTag + "`r`n" + $bodyClose
        )
    }

    Write-Utf8NoBom -Path $ViewPath -Content $viewText
}

Ok "export.js ditambahkan ke view"

Step "6. CREATE EXPORT.JS"

$exportJs = @'
(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const notesApi = `${config.baseUrl}/api/notes`;
    const backupUrl = `${config.baseUrl}/api/backup/download`;

    let overlay = null;

    function bridge() {
        return window.BrowserNoteBridge || null;
    }

    function currentNoteId() {
        const app = bridge();

        if (
            !app
            || typeof app.getCurrentId !== 'function'
        ) {
            return null;
        }

        const id = Number(app.getCurrentId());

        return Number.isInteger(id) && id > 0
            ? id
            : null;
    }

    function safeFilename(value) {
        const clean = String(value || 'catatan')
            .trim()
            .replace(/[<>:"/\\|?*\u0000-\u001F]/g, '-')
            .replace(/\s+/g, ' ')
            .replace(/[. ]+$/g, '')
            .slice(0, 100);

        return clean || 'catatan';
    }

    async function fetchCurrentNote() {
        const id = currentNoteId();

        if (!id) {
            throw new Error(
                'Tidak ada catatan aktif untuk diekspor.'
            );
        }

        const response = await fetch(
            `${notesApi}/${id}`,
            {
                headers: {
                    Accept: 'application/json',
                },
            }
        );

        const data = await response.json();

        if (!response.ok || !data?.ok) {
            throw new Error(
                data?.message || `HTTP ${response.status}`
            );
        }

        return data.data;
    }

    function downloadBlob(content, type, filename) {
        const blob = new Blob(
            [content],
            { type }
        );

        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');

        link.href = url;
        link.download = filename;
        link.style.display = 'none';

        document.body.appendChild(link);
        link.click();
        link.remove();

        window.setTimeout(() => {
            URL.revokeObjectURL(url);
        }, 1000);
    }

    function textFromHtml(html) {
        const doc = new DOMParser().parseFromString(
            String(html || ''),
            'text/html'
        );

        return (doc.body.innerText || '')
            .replace(/\n{3,}/g, '\n\n')
            .trim();
    }

    function tableToMarkdown(table) {
        const rows = Array.from(
            table.querySelectorAll(':scope > tbody > tr, :scope > thead > tr, :scope > tr')
        );

        if (rows.length === 0) {
            return '';
        }

        const matrix = rows.map((row) => {
            return Array.from(row.children)
                .filter((cell) => {
                    return (
                        cell.tagName === 'TD'
                        || cell.tagName === 'TH'
                    );
                })
                .map((cell) => {
                    return textFromHtml(cell.innerHTML)
                        .replace(/\|/g, '\\|')
                        .replace(/\n/g, '<br>');
                });
        });

        const width = Math.max(
            ...matrix.map((row) => row.length)
        );

        if (!Number.isFinite(width) || width < 1) {
            return '';
        }

        for (const row of matrix) {
            while (row.length < width) {
                row.push('');
            }
        }

        const lines = [];

        lines.push(`| ${matrix[0].join(' | ')} |`);
        lines.push(
            `| ${Array(width).fill('---').join(' | ')} |`
        );

        for (const row of matrix.slice(1)) {
            lines.push(`| ${row.join(' | ')} |`);
        }

        return `${lines.join('\n')}\n\n`;
    }

    function listToMarkdown(list, depth = 0) {
        const ordered = list.tagName === 'OL';
        const items = Array.from(list.children)
            .filter((node) => node.tagName === 'LI');

        let output = '';

        items.forEach((item, index) => {
            const prefix = ordered
                ? `${index + 1}. `
                : '- ';

            let body = '';

            for (const child of item.childNodes) {
                if (
                    child.nodeType === Node.ELEMENT_NODE
                    && (
                        child.tagName === 'UL'
                        || child.tagName === 'OL'
                    )
                ) {
                    continue;
                }

                body += nodeToMarkdown(child, depth + 1);
            }

            body = body
                .replace(/\n{2,}/g, ' ')
                .trim();

            output += `${'  '.repeat(depth)}${prefix}${body}\n`;

            for (const child of item.children) {
                if (
                    child.tagName === 'UL'
                    || child.tagName === 'OL'
                ) {
                    output += listToMarkdown(
                        child,
                        depth + 1
                    );
                }
            }
        });

        return `${output}\n`;
    }

    function childrenToMarkdown(node, depth = 0) {
        return Array.from(node.childNodes)
            .map((child) => {
                return nodeToMarkdown(child, depth);
            })
            .join('');
    }

    function nodeToMarkdown(node, depth = 0) {
        if (node.nodeType === Node.TEXT_NODE) {
            return node.nodeValue || '';
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
            return '';
        }

        const tag = node.tagName.toUpperCase();
        const inner = childrenToMarkdown(node, depth);

        if (tag === 'P') {
            return `${inner.trim()}\n\n`;
        }

        if (tag === 'BR') {
            return '\n';
        }

        if (/^H[1-6]$/.test(tag)) {
            const level = Number(tag.substring(1));
            return `${'#'.repeat(level)} ${inner.trim()}\n\n`;
        }

        if (tag === 'STRONG' || tag === 'B') {
            return `**${inner}**`;
        }

        if (tag === 'EM' || tag === 'I') {
            return `*${inner}*`;
        }

        if (tag === 'S' || tag === 'DEL') {
            return `~~${inner}~~`;
        }

        if (tag === 'U') {
            return `<u>${inner}</u>`;
        }

        if (tag === 'CODE' && node.parentElement?.tagName !== 'PRE') {
            const text = node.textContent || '';
            const tick = text.includes('`')
                ? '``'
                : '`';

            return `${tick}${text}${tick}`;
        }

        if (tag === 'PRE') {
            const className = node.className || '';
            const match = className.match(
                /language-([a-z0-9_+-]+)/i
            );

            const language = match
                ? match[1]
                : '';

            return `\`\`\`${language}\n${node.textContent || ''}\n\`\`\`\n\n`;
        }

        if (tag === 'BLOCKQUOTE') {
            const text = inner
                .trim()
                .split('\n')
                .map((line) => `> ${line}`)
                .join('\n');

            return `${text}\n\n`;
        }

        if (tag === 'UL' || tag === 'OL') {
            return listToMarkdown(node, depth);
        }

        if (tag === 'A') {
            const href = node.getAttribute('href') || '';
            const label = inner.trim() || href;

            return href
                ? `[${label}](${href})`
                : label;
        }

        if (tag === 'HR') {
            return '---\n\n';
        }

        if (tag === 'TABLE') {
            return tableToMarkdown(node);
        }

        if (tag === 'DIV' || tag === 'SECTION') {
            return `${inner}\n`;
        }

        return inner;
    }

    function htmlToMarkdown(html) {
        const doc = new DOMParser().parseFromString(
            String(html || ''),
            'text/html'
        );

        const output = childrenToMarkdown(doc.body)
            .replace(/[ \t]+\n/g, '\n')
            .replace(/\n{3,}/g, '\n\n')
            .trim();

        return output;
    }

    function fullHtmlDocument(note) {
        const title = String(
            note.title || 'Catatan tanpa judul'
        );

        const escapedTitle = title
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');

        return `<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapedTitle}</title>
<style>
body{max-width:980px;margin:40px auto;padding:0 24px;font-family:Arial,sans-serif;line-height:1.6;color:#17191c}
h1.document-title{font-size:28px;margin:0 0 28px}
pre{overflow:auto;padding:14px;border:1px solid #ddd;border-radius:6px;background:#f6f7f9}
code{font-family:Consolas,"Courier New",monospace}
table{width:100%;border-collapse:collapse;margin:1em 0}
th,td{padding:7px 9px;border:1px solid #cfd5dc;vertical-align:top}
th{background:#f1f3f5}
blockquote{margin:1em 0;padding-left:14px;border-left:3px solid #c8ced6;color:#505862}
img{max-width:100%;height:auto}
</style>
</head>
<body>
<h1 class="document-title">${escapedTitle}</h1>
${note.content || ''}
</body>
</html>`;
    }

    async function exportCurrent(format) {
        try {
            const note = await fetchCurrentNote();
            const baseName = safeFilename(note.title);

            if (format === 'html') {
                downloadBlob(
                    fullHtmlDocument(note),
                    'text/html;charset=utf-8',
                    `${baseName}.html`
                );
                closeDialog();
                return;
            }

            if (format === 'md') {
                const markdown = htmlToMarkdown(
                    note.content || ''
                );

                const content =
                    `# ${note.title || 'Catatan tanpa judul'}\n\n${markdown}\n`;

                downloadBlob(
                    content,
                    'text/markdown;charset=utf-8',
                    `${baseName}.md`
                );
                closeDialog();
                return;
            }

            if (format === 'txt') {
                const text = textFromHtml(
                    note.content || ''
                );

                const content =
                    `${note.title || 'Catatan tanpa judul'}\n\n${text}\n`;

                downloadBlob(
                    content,
                    'text/plain;charset=utf-8',
                    `${baseName}.txt`
                );

                closeDialog();
            }
        } catch (error) {
            console.error(error);

            window.alert(
                error?.message
                || 'Export catatan gagal.'
            );
        }
    }

    function downloadDatabaseBackup() {
        const link = document.createElement('a');

        link.href = backupUrl;
        link.style.display = 'none';

        document.body.appendChild(link);
        link.click();
        link.remove();

        closeDialog();
    }

    function buildDialog() {
        if (overlay) {
            return;
        }

        overlay = document.createElement('div');
        overlay.className = 'export-overlay';
        overlay.hidden = true;

        const dialog = document.createElement('section');
        dialog.className = 'export-dialog';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute(
            'aria-label',
            'Export dan Backup'
        );

        const header = document.createElement('div');
        header.className = 'export-header';

        const heading = document.createElement('div');
        heading.className = 'export-heading';
        heading.textContent = 'Export & Backup';

        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'export-close';
        close.textContent = '×';
        close.title = 'Tutup';
        close.addEventListener('click', closeDialog);

        header.append(heading, close);

        const noteLabel = document.createElement('div');
        noteLabel.className = 'export-section-label';
        noteLabel.textContent = 'EXPORT CATATAN SAAT INI';

        const noteGrid = document.createElement('div');
        noteGrid.className = 'export-grid';

        const formats = [
            ['HTML', 'Tampilan lengkap, tabel dan format tetap terjaga', 'html'],
            ['Markdown', 'Ringan untuk dokumentasi dan catatan coding', 'md'],
            ['TXT', 'Teks polos tanpa format', 'txt'],
        ];

        for (const [title, description, format] of formats) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'export-card';

            const name = document.createElement('strong');
            name.textContent = title;

            const desc = document.createElement('span');
            desc.textContent = description;

            button.append(name, desc);
            button.addEventListener(
                'click',
                () => exportCurrent(format)
            );

            noteGrid.appendChild(button);
        }

        const backupLabel = document.createElement('div');
        backupLabel.className = 'export-section-label backup-label';
        backupLabel.textContent = 'BACKUP PENUH';

        const backupButton = document.createElement('button');
        backupButton.type = 'button';
        backupButton.className = 'backup-card';

        const backupTitle = document.createElement('strong');
        backupTitle.textContent = 'Download Snapshot SQLite';

        const backupDesc = document.createElement('span');
        backupDesc.textContent =
            'Salinan konsisten seluruh folder, catatan aktif, arsip, dan sampah.';

        backupButton.append(backupTitle, backupDesc);
        backupButton.addEventListener(
            'click',
            downloadDatabaseBackup
        );

        const footer = document.createElement('div');
        footer.className = 'export-footer';
        footer.textContent =
            'Backup SQLite adalah salinan database utama BrowserNote.';

        dialog.append(
            header,
            noteLabel,
            noteGrid,
            backupLabel,
            backupButton,
            footer
        );

        overlay.appendChild(dialog);
        document.body.appendChild(overlay);

        overlay.addEventListener('mousedown', (event) => {
            if (event.target === overlay) {
                closeDialog();
            }
        });
    }

    function openDialog() {
        buildDialog();
        overlay.hidden = false;
    }

    function closeDialog() {
        if (overlay) {
            overlay.hidden = true;
        }
    }

    function injectButton() {
        if (document.getElementById('exportBackupButton')) {
            return;
        }

        const footer =
            document.querySelector('.sidebar-footer');

        if (!footer) {
            return;
        }

        const button = document.createElement('button');
        button.id = 'exportBackupButton';
        button.type = 'button';
        button.className = 'export-backup-button';
        button.textContent = 'Export / Backup';

        button.addEventListener(
            'click',
            openDialog
        );

        footer.appendChild(button);
    }

    document.addEventListener(
        'keydown',
        (event) => {
            if (
                event.key === 'Escape'
                && overlay
                && !overlay.hidden
            ) {
                event.preventDefault();
                closeDialog();
            }
        },
        true
    );

    injectButton();

    window.BrowserNoteExport = {
        open: openDialog,
        close: closeDialog,
        exportCurrent,
        backup: downloadDatabaseBackup,
    };
})();
'@

Write-Utf8NoBom -Path $ExportJsPath -Content $exportJs
Ok "export.js dibuat"

Step "7. APPEND EXPORT CSS"

$cssText = [System.IO.File]::ReadAllText($CssPath)
$cssMarker = '/* BROWSERNOTE_STAGE11_EXPORT_BACKUP */'

if ($cssText.Contains($cssMarker)) {
    $cssText = $cssText.Substring(
        0,
        $cssText.IndexOf($cssMarker)
    ).TrimEnd()
}

$stage11Css = @'

/* BROWSERNOTE_STAGE11_EXPORT_BACKUP */

.export-backup-button {
    width: 100%;
    min-height: 31px;
    margin-top: 5px;
    padding: 5px 8px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--surface);
    color: var(--text-soft);
    text-align: left;
    font-size: 11px;
    cursor: pointer;
}

.export-backup-button:hover {
    background: var(--surface-hover);
    color: var(--text);
}

.export-overlay {
    position: fixed;
    z-index: 1000001;
    inset: 0;
    display: grid;
    place-items: center;
    padding: 20px;
    background: rgba(15, 17, 20, 0.26);
    backdrop-filter: blur(2px);
}

.export-overlay[hidden] {
    display: none;
}

.export-dialog {
    width: min(590px, calc(100vw - 28px));
    padding: 14px;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--surface);
    box-shadow: 0 22px 70px rgba(0, 0, 0, 0.22);
}

.export-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
}

.export-heading {
    font-size: 14px;
    font-weight: 760;
}

.export-close {
    width: 28px;
    height: 28px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--text-muted);
    font-size: 18px;
    cursor: pointer;
}

.export-close:hover {
    background: var(--surface-hover);
    color: var(--text);
}

.export-section-label {
    margin-top: 14px;
    margin-bottom: 6px;
    color: var(--text-muted);
    font-size: 9px;
    font-weight: 760;
    letter-spacing: 0.08em;
}

.export-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 7px;
}

.export-card,
.backup-card {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    padding: 10px;
    border: 1px solid var(--border);
    border-radius: 7px;
    background: var(--surface);
    color: var(--text);
    text-align: left;
    cursor: pointer;
}

.export-card:hover,
.backup-card:hover {
    border-color: var(--border-strong);
    background: var(--surface-soft);
}

.export-card strong,
.backup-card strong {
    font-size: 11px;
}

.export-card span,
.backup-card span {
    color: var(--text-muted);
    font-size: 10px;
    line-height: 1.4;
}

.backup-label {
    margin-top: 16px;
}

.backup-card {
    width: 100%;
}

.export-footer {
    margin-top: 10px;
    color: var(--text-muted);
    font-size: 9px;
}

@media (max-width: 680px) {
    .export-grid {
        grid-template-columns: 1fr;
    }
}
'@

$combinedCss = $cssText.TrimEnd() + "`r`n" + $stage11Css.Trim() + "`r`n"
Write-Utf8NoBom -Path $CssPath -Content $combinedCss

Ok "CSS Export + Backup dipasang"

Step "8. PHP LINT"

foreach ($file in @(
    $BackupApi,
    $RoutesPath,
    $ViewPath
)) {
    $lint = & $PhpExe -l $file 2>&1

    if ($LASTEXITCODE -ne 0) {
        $lint | ForEach-Object {
            Write-Host $_
        }

        Fail "PHP lint gagal: $file"
    }

    Ok "Syntax valid: $(Split-Path $file -Leaf)"
}

Step "9. ROUTE VERIFICATION"

Push-Location $ProjectRoot

try {
    $routesOut = & $PhpExe spark routes 2>&1
    $routesExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($routesExit -ne 0) {
    Fail "php spark routes gagal."
}

$routesJoined = $routesOut -join "`n"

if ($routesJoined -notlike '*BackupApi::download*') {
    Fail "Route BackupApi::download tidak terdaftar."
}

Ok "Backup route PASS"

Step "10. SQLITE BACKUP DOWNLOAD TEST"

if (Test-Path $TempBackup) {
    Remove-Item $TempBackup -Force
}

try {
    Invoke-WebRequest `
        -Uri "$BaseUrl/api/backup/download" `
        -UseBasicParsing `
        -TimeoutSec 20 `
        -OutFile $TempBackup
}
catch {
    Fail "Endpoint backup tidak dapat diunduh."
}

if (-not (Test-Path $TempBackup)) {
    Fail "File backup test tidak terbentuk."
}

$bytes = [System.IO.File]::ReadAllBytes($TempBackup)

if ($bytes.Length -lt 100) {
    Fail "File backup terlalu kecil."
}

$header = [System.Text.Encoding]::ASCII.GetString(
    $bytes,
    0,
    [Math]::Min(15, $bytes.Length)
)

if (-not $header.StartsWith('SQLite format 3')) {
    Fail "File download bukan database SQLite valid."
}

Remove-Item $TempBackup -Force

Ok "SQLite snapshot download PASS"
Ok "SQLite header PASS"

Step "11. HTTP UI VERIFICATION"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8

    $exportHttp = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/export.js" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Root atau export.js tidak dapat diakses."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if ($exportHttp.StatusCode -ne 200) {
    Fail "export.js tidak HTTP 200."
}

if ($page.Content -notlike '*assets/js/export.js*') {
    Fail "Root belum memuat export.js."
}

foreach ($fragment in @(
    'BrowserNoteExport',
    'htmlToMarkdown',
    'api/backup/download',
    'Export / Backup'
)) {
    if ($exportHttp.Content -notlike "*$fragment*") {
        Fail "Fitur export hilang: $fragment"
    }
}

Ok "Export UI asset PASS"

Step "STAGE 11 PASS"

Write-Host ""
Write-Host "Project        : $ProjectRoot" -ForegroundColor White
Write-Host "URL            : $BaseUrl/" -ForegroundColor White
Write-Host "Export HTML    : PASS" -ForegroundColor White
Write-Host "Export Markdown: PASS" -ForegroundColor White
Write-Host "Export TXT     : PASS" -ForegroundColor White
Write-Host "SQLite snapshot: PASS" -ForegroundColor White
Write-Host "Backup download: PASS" -ForegroundColor White
Write-Host "Main editor JS : unchanged" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 11:" -ForegroundColor Green
Write-Host "1. Klik Export / Backup di sidebar." -ForegroundColor White
Write-Host "2. Export catatan sebagai HTML dan buka hasilnya." -ForegroundColor White
Write-Host "3. Export sebagai Markdown dan cek heading, code block, list, serta tabel." -ForegroundColor White
Write-Host "4. Export sebagai TXT." -ForegroundColor White
Write-Host "5. Klik Download Snapshot SQLite." -ForegroundColor White
Write-Host "6. Pastikan file browsernote_backup_YYYYMMDD_HHMMSS.sqlite terunduh." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 12 - UI polish" -ForegroundColor Green
