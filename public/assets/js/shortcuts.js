(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiBase = `${config.baseUrl}/api/notes`;
    const quickOpenKey = 'browsernote.quickOpenNoteId';

    let quickOverlay = null;
    let helpOverlay = null;
    let quickTitle = null;
    let quickBody = null;
    let quickSave = null;

    function bridge() {
        return window.BrowserNoteBridge || null;
    }

    function getCurrentFolderId() {
        const select = document.getElementById('noteFolderSelect');

        if (!select || select.disabled) {
            return null;
        }

        const value = String(select.value || '').trim();

        return value === ''
            ? null
            : Number(value);
    }

    function escapeHtml(value) {
        return String(value)
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function plainTextToHtml(value) {
        const normalized = String(value || '')
            .replace(/\r\n/g, '\n')
            .trim();

        if (normalized === '') {
            return '<p></p>';
        }

        return normalized
            .split(/\n{2,}/)
            .map((paragraph) => {
                const safe = escapeHtml(paragraph)
                    .replace(/\n/g, '<br>');

                return `<p>${safe}</p>`;
            })
            .join('');
    }

    function deriveTitle(title, body) {
        const cleanTitle = String(title || '').trim();

        if (cleanTitle !== '') {
            return cleanTitle.slice(0, 255);
        }

        const firstLine = String(body || '')
            .trim()
            .split(/\r?\n/)[0]
            .trim();

        if (firstLine !== '') {
            return firstLine.slice(0, 90);
        }

        return 'Quick Note';
    }

    async function createQuickNote() {
        const body = quickBody.value;
        const title = deriveTitle(
            quickTitle.value,
            body
        );

        if (
            String(body).trim() === ''
            && String(quickTitle.value).trim() === ''
        ) {
            quickBody.focus();
            return;
        }

        quickSave.disabled = true;
        quickSave.textContent = 'Menyimpan...';

        try {
            const response = await fetch(apiBase, {
                method: 'POST',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    title,
                    content: plainTextToHtml(body),
                    folder_id: getCurrentFolderId(),
                }),
            });

            const data = await response.json();

            if (!response.ok || !data?.ok) {
                throw new Error(
                    data?.message || `HTTP ${response.status}`
                );
            }

            sessionStorage.setItem(
                quickOpenKey,
                String(data.data.id)
            );

            window.location.reload();
        } catch (error) {
            console.error(error);

            quickSave.disabled = false;
            quickSave.textContent =
                'Simpan Quick Note';

            window.alert(
                error?.message
                || 'Quick Note gagal disimpan.'
            );
        }
    }

    function buildQuickNote() {
        if (quickOverlay) {
            return;
        }

        quickOverlay = document.createElement('div');
        quickOverlay.className = 'quick-note-overlay';
        quickOverlay.hidden = true;

        const dialog = document.createElement('section');
        dialog.className = 'quick-note-dialog';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-label', 'Quick Note');

        const header = document.createElement('div');
        header.className = 'quick-note-header';

        const heading = document.createElement('div');
        heading.className = 'quick-note-heading';
        heading.textContent = 'Quick Note';

        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'quick-note-close';
        close.textContent = '×';
        close.title = 'Tutup';
        close.addEventListener('click', closeQuickNote);

        header.append(heading, close);

        quickTitle = document.createElement('input');
        quickTitle.type = 'text';
        quickTitle.className = 'quick-note-title';
        quickTitle.placeholder =
            'Judul opsional — kosongkan untuk memakai baris pertama';
        quickTitle.maxLength = 255;
        quickTitle.autocomplete = 'off';

        quickBody = document.createElement('textarea');
        quickBody.className = 'quick-note-body';
        quickBody.placeholder = 'Tulis catatan singkat...';
        quickBody.spellcheck = true;

        const footer = document.createElement('div');
        footer.className = 'quick-note-footer';

        const hint = document.createElement('div');
        hint.className = 'quick-note-hint';
        hint.textContent =
            'Ctrl+Enter simpan · Esc batal';

        const actions = document.createElement('div');
        actions.className = 'quick-note-actions';

        const cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.className = 'quick-note-secondary';
        cancel.textContent = 'Batal';
        cancel.addEventListener('click', closeQuickNote);

        quickSave = document.createElement('button');
        quickSave.type = 'button';
        quickSave.className = 'quick-note-primary';
        quickSave.textContent = 'Simpan Quick Note';
        quickSave.addEventListener(
            'click',
            createQuickNote
        );

        actions.append(cancel, quickSave);
        footer.append(hint, actions);

        dialog.append(
            header,
            quickTitle,
            quickBody,
            footer
        );

        quickOverlay.appendChild(dialog);
        document.body.appendChild(quickOverlay);

        quickOverlay.addEventListener(
            'mousedown',
            (event) => {
                if (event.target === quickOverlay) {
                    closeQuickNote();
                }
            }
        );

        quickOverlay.addEventListener(
            'keydown',
            (event) => {
                if (event.key === 'Escape') {
                    event.preventDefault();
                    closeQuickNote();
                    return;
                }

                if (
                    (event.ctrlKey || event.metaKey)
                    && event.key === 'Enter'
                ) {
                    event.preventDefault();
                    createQuickNote();
                }
            }
        );
    }

    function openQuickNote() {
        buildQuickNote();

        if (helpOverlay) {
            helpOverlay.hidden = true;
        }

        quickTitle.value = '';
        quickBody.value = '';
        quickSave.disabled = false;
        quickSave.textContent =
            'Simpan Quick Note';

        quickOverlay.hidden = false;

        window.setTimeout(() => {
            quickBody.focus();
        }, 0);
    }

    function closeQuickNote() {
        if (quickOverlay) {
            quickOverlay.hidden = true;
        }
    }

    function buildHelp() {
        if (helpOverlay) {
            return;
        }

        helpOverlay = document.createElement('div');
        helpOverlay.className = 'shortcut-overlay';
        helpOverlay.hidden = true;

        const dialog = document.createElement('section');
        dialog.className = 'shortcut-dialog';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute(
            'aria-label',
            'Keyboard Shortcuts'
        );

        const header = document.createElement('div');
        header.className = 'shortcut-header';

        const heading = document.createElement('div');
        heading.className = 'shortcut-heading';
        heading.textContent = 'Keyboard Shortcuts';

        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'quick-note-close';
        close.textContent = '×';
        close.addEventListener(
            'click',
            closeHelp
        );

        header.append(heading, close);

        const shortcuts = [
            ['Ctrl + N', 'Catatan baru'],
            ['Ctrl + Alt + N', 'Quick Note'],
            ['Ctrl + S', 'Simpan sekarang'],
            ['Ctrl + F', 'Cari judul dan isi'],
            ['Ctrl + Enter', 'Simpan Quick Note'],
            ['Esc', 'Tutup / bersihkan pencarian'],
            ['Ctrl + /', 'Bantuan shortcut'],
        ];

        const list = document.createElement('div');
        list.className = 'shortcut-list';

        for (const [keys, label] of shortcuts) {
            const row = document.createElement('div');
            row.className = 'shortcut-row';

            const key = document.createElement('kbd');
            key.textContent = keys;

            const text = document.createElement('span');
            text.textContent = label;

            row.append(key, text);
            list.appendChild(row);
        }

        dialog.append(header, list);
        helpOverlay.appendChild(dialog);
        document.body.appendChild(helpOverlay);

        helpOverlay.addEventListener(
            'mousedown',
            (event) => {
                if (event.target === helpOverlay) {
                    closeHelp();
                }
            }
        );
    }

    function openHelp() {
        buildHelp();

        if (quickOverlay) {
            quickOverlay.hidden = true;
        }

        helpOverlay.hidden = false;
    }

    function closeHelp() {
        if (helpOverlay) {
            helpOverlay.hidden = true;
        }
    }

    function injectButtons() {
        if (!document.getElementById('quickNoteButton')) {
            const newNoteButton =
                document.getElementById('newNoteButton');

            if (newNoteButton) {
                const quick = document.createElement('button');
                quick.id = 'quickNoteButton';
                quick.type = 'button';
                quick.className = 'quick-note-launcher';

                const label = document.createElement('span');
                label.textContent = 'Quick Note';

                const keys = document.createElement('kbd');
                keys.textContent = 'Ctrl+Alt+N';

                quick.append(label, keys);
                quick.addEventListener(
                    'click',
                    openQuickNote
                );

                newNoteButton.insertAdjacentElement(
                    'afterend',
                    quick
                );
            }
        }

        if (!document.getElementById('shortcutHelpButton')) {
            const footer =
                document.querySelector('.sidebar-footer');

            if (footer) {
                const help = document.createElement('button');
                help.id = 'shortcutHelpButton';
                help.type = 'button';
                help.className = 'shortcut-help-button';

                const label = document.createElement('span');
                label.textContent = 'Shortcut';

                const keys = document.createElement('kbd');
                keys.textContent = 'Ctrl+/';

                help.append(label, keys);
                help.addEventListener(
                    'click',
                    openHelp
                );

                footer.appendChild(help);
            }
        }
    }

    function openQuickCreatedNote() {
        const noteId = Number(
            sessionStorage.getItem(quickOpenKey)
        );

        if (!Number.isInteger(noteId) || noteId < 1) {
            return;
        }

        let attempts = 0;

        const timer = window.setInterval(async () => {
            attempts += 1;

            const app = bridge();

            if (
                app
                && typeof app.openNoteById === 'function'
            ) {
                window.clearInterval(timer);

                try {
                    await app.openNoteById(
                        noteId,
                        'active'
                    );

                    sessionStorage.removeItem(
                        quickOpenKey
                    );
                } catch (error) {
                    console.error(error);
                }

                return;
            }

            if (attempts >= 40) {
                window.clearInterval(timer);
            }
        }, 150);
    }

    document.addEventListener(
        'keydown',
        (event) => {
            const key = event.key.toLowerCase();

            if (
                (event.ctrlKey || event.metaKey)
                && event.altKey
                && key === 'n'
            ) {
                event.preventDefault();
                event.stopPropagation();
                openQuickNote();
                return;
            }

            if (
                (event.ctrlKey || event.metaKey)
                && key === '/'
            ) {
                event.preventDefault();
                event.stopPropagation();
                openHelp();
                return;
            }

            if (event.key === 'Escape') {
                if (
                    quickOverlay
                    && !quickOverlay.hidden
                ) {
                    event.preventDefault();
                    closeQuickNote();
                    return;
                }

                if (
                    helpOverlay
                    && !helpOverlay.hidden
                ) {
                    event.preventDefault();
                    closeHelp();
                }
            }
        },
        true
    );

    injectButtons();
    openQuickCreatedNote();

    window.BrowserNoteQuickNote = {
        open: openQuickNote,
        close: closeQuickNote,
    };

    window.BrowserNoteShortcuts = {
        open: openHelp,
        close: closeHelp,
    };
})();