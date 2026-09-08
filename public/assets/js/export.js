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