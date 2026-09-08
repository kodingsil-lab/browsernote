(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiUrl = `${config.baseUrl}/api/search`;
    const debounceMs = 240;

    const input = document.getElementById('searchInput');
    const clearButton = document.getElementById('searchClearButton');
    const noteList = document.getElementById('noteList');
    const noteCount = document.getElementById('noteCount');
    const heading = document.getElementById('noteListHeading');

    if (!input || !clearButton || !noteList || !noteCount || !heading) {
        console.error('BrowserNote Search UI tidak lengkap.');
        return;
    }

    let timer = null;
    let requestSeq = 0;
    let query = '';
    let results = [];

    function bridge() {
        return window.BrowserNoteBridge || null;
    }

    function formatDate(value) {
        if (!value) {
            return '';
        }

        const normalized = value.includes('T')
            ? value
            : value.replace(' ', 'T');

        const date = new Date(normalized);

        if (Number.isNaN(date.getTime())) {
            return value;
        }

        return new Intl.DateTimeFormat('id-ID', {
            day: '2-digit',
            month: 'short',
            hour: '2-digit',
            minute: '2-digit',
        }).format(date);
    }

    function hasQuery() {
        return query.trim() !== '';
    }

    function focusSearch() {
        input.focus();
        input.select();
    }

    function restoreNormalList() {
        heading.textContent = 'CATATAN';

        if (bridge()) {
            bridge().refresh();
        }
    }

    function clearSearch({ keepFocus = false } = {}) {
        window.clearTimeout(timer);
        timer = null;
        requestSeq += 1;

        query = '';
        results = [];

        input.value = '';
        clearButton.hidden = true;

        restoreNormalList();

        if (keepFocus) {
            input.focus();
        }
    }

    async function apiSearch(value) {
        const response = await fetch(
            `${apiUrl}?q=${encodeURIComponent(value)}&status=all&limit=100`,
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

        return data;
    }

    function renderResults() {
        heading.textContent = 'HASIL PENCARIAN';
        noteList.innerHTML = '';
        noteCount.textContent = String(results.length);

        if (results.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'mode-empty';
            empty.textContent =
                `Tidak ditemukan catatan untuk "${query}".`;

            noteList.appendChild(empty);
            return;
        }

        for (const note of results) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'note-item search-result';

            const title = document.createElement('div');
            title.className = 'note-item-title';
            title.textContent =
                note.title || 'Catatan tanpa judul';

            const meta = document.createElement('div');
            meta.className = 'note-item-meta';

            const status = Number(note.is_archived) === 1
                ? 'Arsip'
                : 'Aktif';

            const folder = note.folder_name
                ? ` · ${note.folder_name}`
                : '';

            meta.textContent =
                `${status}${folder} · ${formatDate(note.updated_at)}`;

            button.append(title, meta);

            if (note.snippet) {
                const snippet = document.createElement('div');
                snippet.className = 'search-result-snippet';
                snippet.textContent = note.snippet;
                button.appendChild(snippet);
            }

            button.addEventListener('click', async () => {
                const app = bridge();

                if (!app) {
                    return;
                }

                try {
                    const mode = Number(note.is_archived) === 1
                        ? 'archived'
                        : 'active';

                    await app.openNoteById(note.id, mode);
                    clearSearch();
                } catch (error) {
                    console.error(error);
                }
            });

            noteList.appendChild(button);
        }
    }

    async function performSearch(value) {
        const clean = String(value || '').trim();

        if (clean === '') {
            clearSearch();
            return;
        }

        const seq = ++requestSeq;

        heading.textContent = 'HASIL PENCARIAN';
        noteList.innerHTML =
            '<div class="sidebar-empty">Mencari...</div>';
        noteCount.textContent = '…';

        try {
            const data = await apiSearch(clean);

            if (
                seq !== requestSeq
                || clean !== query
            ) {
                return;
            }

            results = Array.isArray(data.data)
                ? data.data
                : [];

            renderResults();
        } catch (error) {
            console.error(error);

            if (seq !== requestSeq) {
                return;
            }

            noteList.innerHTML =
                '<div class="sidebar-empty">Pencarian gagal.</div>';

            noteCount.textContent = '!';
        }
    }

    function scheduleSearch() {
        window.clearTimeout(timer);

        query = input.value.trim();
        clearButton.hidden = query === '';

        if (!hasQuery()) {
            clearSearch();
            return;
        }

        timer = window.setTimeout(() => {
            timer = null;
            performSearch(query);
        }, debounceMs);
    }

    function attachEditorShortcut() {
        if (!window.tinymce) {
            return;
        }

        const editor = window.tinymce.get('noteEditor');

        if (!editor || editor.__browserNoteSearchBound) {
            return;
        }

        editor.__browserNoteSearchBound = true;

        editor.on('keydown', (event) => {
            if (
                (event.ctrlKey || event.metaKey)
                && event.key.toLowerCase() === 'f'
            ) {
                event.preventDefault();
                focusSearch();
            }
        });
    }

    input.addEventListener('input', scheduleSearch);

    input.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            event.preventDefault();
            clearSearch({ keepFocus: true });
        }

        if (
            event.key === 'Enter'
            && results.length > 0
        ) {
            event.preventDefault();

            const first = results[0];
            const app = bridge();

            if (!app) {
                return;
            }

            const mode = Number(first.is_archived) === 1
                ? 'archived'
                : 'active';

            app.openNoteById(first.id, mode)
                .then(() => clearSearch())
                .catch(console.error);
        }
    });

    clearButton.addEventListener('click', () => {
        clearSearch({ keepFocus: true });
    });

    document.addEventListener('keydown', (event) => {
        if (
            (event.ctrlKey || event.metaKey)
            && event.key.toLowerCase() === 'f'
        ) {
            event.preventDefault();
            focusSearch();
            return;
        }

        if (
            event.key === 'Escape'
            && hasQuery()
            && document.activeElement !== input
        ) {
            clearSearch();
        }
    });

    const shortcutTimer = window.setInterval(() => {
        attachEditorShortcut();

        if (
            window.tinymce
            && window.tinymce.get('noteEditor')
        ) {
            window.clearInterval(shortcutTimer);
        }
    }, 250);

    window.BrowserNoteSearch = {
        focus: focusSearch,

        clear() {
            clearSearch();
        },

        run(value) {
            input.value = String(value || '');
            query = input.value.trim();
            clearButton.hidden = query === '';

            return performSearch(query);
        },

        getQuery() {
            return query;
        },

        getResults() {
            return [...results];
        },
    };
})();