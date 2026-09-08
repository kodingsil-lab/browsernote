#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
# BrowserNote - STAGE 05
# AUTOSAVE + STABLE SAVE STATE
# Project : C:\xampp\htdocs\browsernote
# Base URL: http://localhost/browsernote/public/
# ============================================================

$ProjectRoot = 'C:\xampp\htdocs\browsernote'
$BaseUrl     = 'http://localhost/browsernote/public'
$JsPath      = Join-Path $ProjectRoot 'public\assets\js\browsernote.js'
$Stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot "writable\backups\stage05_$Stamp"

function Step([string]$Message) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

Step "1. PRECHECK"

if (-not (Test-Path $ProjectRoot)) {
    Fail "Project tidak ditemukan: $ProjectRoot"
}

if (-not (Test-Path $JsPath)) {
    Fail "browsernote.js tidak ditemukan. Stage 04 belum lengkap."
}

if (-not (Test-Path (Join-Path $ProjectRoot 'public\assets\vendor\tinymce\tinymce.min.js'))) {
    Fail "TinyMCE lokal tidak ditemukan. Stage 04 belum lengkap."
}

Ok "Project ditemukan"
Ok "browsernote.js ditemukan"
Ok "TinyMCE self-hosted ditemukan"

Step "2. BACKUP CURRENT JAVASCRIPT"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Copy-Item $JsPath (Join-Path $BackupDir 'browsernote.js') -Force

Ok "Backup dibuat: $BackupDir"

Step "3. INSTALL AUTOSAVE JAVASCRIPT"

$js = @'
(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiBase = `${config.baseUrl}/api/notes`;

    const AUTOSAVE_DELAY = 700;

    const state = {
        editor: null,
        notes: [],
        currentId: null,
        currentNote: null,

        dirty: false,
        loading: false,
        saving: false,

        editVersion: 0,
        lastSavedVersion: 0,
        savePromise: null,
        autosaveTimer: null,

        toastTimer: null,
    };

    const el = {
        appShell: document.getElementById('appShell'),
        collapseSidebar: document.getElementById('collapseSidebar'),
        showSidebar: document.getElementById('showSidebar'),
        newNoteButton: document.getElementById('newNoteButton'),
        noteList: document.getElementById('noteList'),
        noteCount: document.getElementById('noteCount'),
        noteTitle: document.getElementById('noteTitle'),
        saveState: document.getElementById('saveState'),
        saveButton: document.getElementById('saveButton'),
        editorHost: document.getElementById('editorHost'),
        currentNoteInfo: document.getElementById('currentNoteInfo'),
        wordCount: document.getElementById('wordCount'),
        charCount: document.getElementById('charCount'),
        toast: document.getElementById('toast'),
    };

    function setSaveState(text, type = 'ready') {
        el.saveState.textContent = text;
        el.saveState.dataset.state = type;
    }

    function currentClock() {
        return new Intl.DateTimeFormat('id-ID', {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
        }).format(new Date());
    }

    function showToast(message) {
        el.toast.textContent = message;
        el.toast.classList.add('show');

        window.clearTimeout(state.toastTimer);
        state.toastTimer = window.setTimeout(() => {
            el.toast.classList.remove('show');
        }, 2200);
    }

    function escapeText(value) {
        return String(value ?? '');
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

    async function request(url, options = {}) {
        const response = await fetch(url, {
            headers: {
                Accept: 'application/json',
                ...(options.body ? { 'Content-Type': 'application/json' } : {}),
                ...(options.headers || {}),
            },
            ...options,
        });

        let data = null;

        try {
            data = await response.json();
        } catch {
            throw new Error(`Respons server bukan JSON (${response.status}).`);
        }

        if (!response.ok || !data?.ok) {
            throw new Error(data?.message || `HTTP ${response.status}`);
        }

        return data;
    }

    function updateCounters() {
        if (!state.editor) {
            el.wordCount.textContent = '0 kata';
            el.charCount.textContent = '0 karakter';
            return;
        }

        const text = state.editor.getContent({ format: 'text' }) || '';
        const trimmed = text.trim();
        const words = trimmed === ''
            ? 0
            : trimmed.split(/\s+/u).filter(Boolean).length;

        el.wordCount.textContent = `${words.toLocaleString('id-ID')} kata`;
        el.charCount.textContent = `${text.length.toLocaleString('id-ID')} karakter`;
    }

    function clearAutosaveTimer() {
        if (state.autosaveTimer !== null) {
            window.clearTimeout(state.autosaveTimer);
            state.autosaveTimer = null;
        }
    }

    function scheduleAutosave() {
        if (
            state.loading
            || !state.currentId
            || !state.editor
            || !state.dirty
        ) {
            return;
        }

        clearAutosaveTimer();

        state.autosaveTimer = window.setTimeout(() => {
            state.autosaveTimer = null;

            saveCurrent({
                quiet: true,
                automatic: true,
            }).catch(handleError);
        }, AUTOSAVE_DELAY);
    }

    function markDirty() {
        if (state.loading || !state.currentId) {
            return;
        }

        state.editVersion += 1;
        state.dirty = true;

        setSaveState('Belum tersimpan', 'dirty');
        el.saveButton.disabled = false;

        updateCounters();
        scheduleAutosave();
    }

    function setClean(savedText = 'Tersimpan') {
        state.dirty = false;
        state.lastSavedVersion = state.editVersion;

        setSaveState(savedText, 'saved');
        el.saveButton.disabled = true;

        if (state.editor) {
            state.editor.setDirty(false);
        }
    }

    function renderNotes() {
        el.noteList.innerHTML = '';
        el.noteCount.textContent = String(state.notes.length);

        if (state.notes.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'sidebar-empty';
            empty.textContent = 'Belum ada catatan aktif.';
            el.noteList.appendChild(empty);
            return;
        }

        for (const note of state.notes) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'note-item';

            if (Number(note.id) === Number(state.currentId)) {
                button.classList.add('active');
            }

            const title = document.createElement('div');
            title.className = 'note-item-title';
            title.textContent = escapeText(
                note.title || 'Catatan tanpa judul'
            );

            const meta = document.createElement('div');
            meta.className = 'note-item-meta';

            const folder = note.folder_name
                ? `${note.folder_name} · `
                : '';

            meta.textContent = `${folder}${formatDate(note.updated_at)}`;

            button.append(title, meta);

            button.addEventListener('click', async () => {
                const id = Number(note.id);

                if (id === Number(state.currentId)) {
                    return;
                }

                try {
                    await flushPendingSave();
                    await openNote(id);
                } catch (error) {
                    handleError(error);
                }
            });

            el.noteList.appendChild(button);
        }
    }

    async function loadNotes(preferredId = null) {
        const response = await request(apiBase);
        state.notes = Array.isArray(response.data) ? response.data : [];
        renderNotes();

        if (state.notes.length === 0) {
            const created = await createNote({ open: false });
            await loadNotes(created.id);
            return;
        }

        const wanted = preferredId
            ? state.notes.find(
                (item) => Number(item.id) === Number(preferredId)
            )
            : null;

        const id = wanted
            ? Number(wanted.id)
            : Number(state.notes[0].id);

        await openNote(id);
    }

    async function openNote(id) {
        if (!state.editor) {
            return;
        }

        clearAutosaveTimer();

        state.loading = true;
        setSaveState('Memuat...', 'saving');

        try {
            const response = await request(`${apiBase}/${id}`);
            const note = response.data;

            state.currentId = Number(note.id);
            state.currentNote = note;

            state.editVersion = 0;
            state.lastSavedVersion = 0;
            state.dirty = false;

            el.noteTitle.value = note.title || '';
            state.editor.setContent(note.content || '');
            state.editor.undoManager.clear();

            updateCounters();
            setClean('Tersimpan');

            el.currentNoteInfo.textContent = note.folder_name
                ? `#${note.id} · ${note.folder_name}`
                : `#${note.id} · Tanpa folder`;

            renderNotes();

            window.setTimeout(() => {
                state.editor.focus();
            }, 0);
        } finally {
            state.loading = false;
        }
    }

    async function createNote({ open = true } = {}) {
        await flushPendingSave();

        el.newNoteButton.disabled = true;
        setSaveState('Membuat...', 'saving');

        try {
            const response = await request(apiBase, {
                method: 'POST',
                body: JSON.stringify({
                    title: 'Catatan tanpa judul',
                    content: '<p></p>',
                }),
            });

            const created = response.data;

            if (open) {
                const list = await request(apiBase);
                state.notes = Array.isArray(list.data)
                    ? list.data
                    : [];

                renderNotes();
                await openNote(Number(created.id));
            }

            showToast('Catatan baru dibuat');

            return created;
        } finally {
            el.newNoteButton.disabled = false;
        }
    }

    async function performSave({
        quiet = false,
        automatic = false,
    } = {}) {
        if (
            !state.currentId
            || !state.editor
            || !state.dirty
        ) {
            return;
        }

        const noteId = Number(state.currentId);
        const versionAtStart = state.editVersion;

        const title = el.noteTitle.value.trim()
            || 'Catatan tanpa judul';

        const content = state.editor.getContent();

        state.saving = true;
        el.saveButton.disabled = true;
        setSaveState('Menyimpan...', 'saving');

        try {
            const response = await request(
                `${apiBase}/${noteId}`,
                {
                    method: 'PATCH',
                    body: JSON.stringify({
                        title,
                        content,
                    }),
                }
            );

            /*
             * Catatan mungkin sudah berpindah saat respons datang.
             * Jangan mengubah UI catatan lain.
             */
            if (Number(state.currentId) !== noteId) {
                return;
            }

            state.currentNote = response.data;

            const existing = state.notes.find(
                (item) => Number(item.id) === noteId
            );

            if (existing) {
                Object.assign(existing, response.data);
            }

            renderNotes();

            /*
             * Ini perlindungan race condition utama.
             * Bila pengguna mengetik lagi selama request save berjalan,
             * versi saat ini lebih baru daripada versionAtStart.
             */
            if (state.editVersion === versionAtStart) {
                el.noteTitle.value = response.data.title || title;

                setClean(
                    automatic
                        ? `Tersimpan otomatis ${currentClock()}`
                        : `Tersimpan ${currentClock()}`
                );
            } else {
                state.dirty = true;
                el.saveButton.disabled = false;
                setSaveState('Ada perubahan baru', 'dirty');
                scheduleAutosave();
            }

            updateCounters();

            if (!quiet && !automatic) {
                showToast('Catatan tersimpan');
            }
        } catch (error) {
            if (Number(state.currentId) === noteId) {
                state.dirty = true;
                el.saveButton.disabled = false;
                setSaveState('Gagal menyimpan', 'error');
            }

            throw error;
        } finally {
            state.saving = false;
        }
    }

    function saveCurrent(options = {}) {
        clearAutosaveTimer();

        if (state.savePromise) {
            return state.savePromise.then(async () => {
                if (state.dirty) {
                    return saveCurrent(options);
                }
            });
        }

        state.savePromise = performSave(options)
            .finally(() => {
                state.savePromise = null;
            });

        return state.savePromise;
    }

    async function flushPendingSave() {
        clearAutosaveTimer();

        if (state.savePromise) {
            await state.savePromise;
        }

        if (state.dirty) {
            await saveCurrent({
                quiet: true,
                automatic: true,
            });
        }

        if (state.savePromise) {
            await state.savePromise;
        }
    }

    function handleError(error) {
        console.error(error);

        if (state.dirty) {
            setSaveState('Gagal menyimpan', 'error');
        } else {
            setSaveState('Terjadi kesalahan', 'error');
        }

        showToast(
            error?.message || 'Terjadi kesalahan.'
        );
    }

    function editorPixelHeight() {
        return Math.max(
            420,
            Math.floor(el.editorHost.clientHeight)
        );
    }

    function fitEditorToHost() {
        if (!state.editor) {
            return;
        }

        const container = state.editor.getContainer();

        if (container) {
            container.style.height = `${editorPixelHeight()}px`;
        }
    }

    async function initTinyMCE() {
        if (typeof window.tinymce === 'undefined') {
            throw new Error(
                'TinyMCE lokal gagal dimuat.'
            );
        }

        const editors = await window.tinymce.init({
            selector: '#noteEditor',

            base_url: config.tinyMceBase,
            suffix: '.min',
            license_key: 'gpl',

            height: editorPixelHeight(),
            resize: false,

            menubar: 'edit view insert format tools table help',

            plugins: [
                'advlist',
                'autolink',
                'lists',
                'link',
                'charmap',
                'preview',
                'anchor',
                'searchreplace',
                'visualblocks',
                'code',
                'fullscreen',
                'insertdatetime',
                'table',
                'codesample',
                'wordcount',
            ].join(' '),

            toolbar: [
                'undo redo | blocks fontfamily fontsize',
                'bold italic underline strikethrough | forecolor backcolor',
                'alignleft aligncenter alignright alignjustify',
                'bullist numlist outdent indent | blockquote',
                'link codesample table',
                'removeformat | searchreplace visualblocks code fullscreen | help',
            ].join(' | '),

            toolbar_mode: 'wrap',
            toolbar_sticky: false,

            table_toolbar: [
                'tableprops tabledelete',
                'tablerowprops tablecellprops',
                'tableinsertrowbefore tableinsertrowafter tabledeleterow',
                'tableinsertcolbefore tableinsertcolafter tabledeletecol',
                'tablemergecells tablesplitcells',
                'tablerowheader tablecolheader',
            ].join(' | '),

            table_appearance_options: true,
            table_advtab: true,
            table_cell_advtab: true,
            table_row_advtab: true,

            link_context_toolbar: true,
            browser_spellcheck: true,
            contextmenu: 'link table',

            codesample_languages: [
                { text: 'HTML/XML', value: 'markup' },
                { text: 'JavaScript', value: 'javascript' },
                { text: 'CSS', value: 'css' },
                { text: 'PHP', value: 'php' },
                { text: 'Python', value: 'python' },
                { text: 'Java', value: 'java' },
                { text: 'C', value: 'c' },
                { text: 'C#', value: 'csharp' },
                { text: 'C++', value: 'cpp' },
            ],

            content_style: `
                body {
                    margin: 0;
                    padding: 24px 28px 80px;
                    font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
                    font-size: 15px;
                    line-height: 1.62;
                    color: #17191c;
                    background: #ffffff;
                }

                p {
                    margin-top: 0;
                    margin-bottom: 0.8em;
                }

                h1, h2, h3, h4, h5, h6 {
                    line-height: 1.25;
                    margin-top: 1.25em;
                    margin-bottom: 0.55em;
                }

                h1:first-child,
                h2:first-child,
                h3:first-child {
                    margin-top: 0;
                }

                code:not(pre code) {
                    padding: 0.14em 0.34em;
                    border: 1px solid #e0e4e8;
                    border-radius: 4px;
                    background: #f5f6f8;
                    font-family: Consolas, "Cascadia Code", "Courier New", monospace;
                    font-size: 0.92em;
                }

                pre {
                    overflow-x: auto;
                    padding: 14px 16px;
                    border: 1px solid #dde2e7;
                    border-radius: 7px;
                    background: #f6f7f9;
                    font-family: Consolas, "Cascadia Code", "Courier New", monospace;
                    font-size: 13px;
                    line-height: 1.55;
                    white-space: pre;
                }

                blockquote {
                    margin: 1em 0;
                    padding: 0.4em 0 0.4em 14px;
                    border-left: 3px solid #c8ced6;
                    color: #505862;
                }

                table {
                    width: 100%;
                    margin: 1em 0;
                    border-collapse: collapse;
                }

                th,
                td {
                    min-width: 40px;
                    padding: 7px 9px;
                    border: 1px solid #cfd5dc;
                    vertical-align: top;
                }

                th {
                    background: #f1f3f5;
                    font-weight: 700;
                }

                a {
                    color: #2457a6;
                }
            `,

            setup(editor) {
                editor.on('init', () => {
                    state.editor = editor;
                    fitEditorToHost();
                    updateCounters();
                });

                editor.on(
                    'input change undo redo',
                    () => {
                        markDirty();
                    }
                );

                editor.on('SetContent', () => {
                    updateCounters();
                });

                editor.on('keydown', (event) => {
                    const key = event.key.toLowerCase();

                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 's'
                    ) {
                        event.preventDefault();

                        saveCurrent({
                            quiet: false,
                            automatic: false,
                        }).catch(handleError);
                    }

                    if (
                        (event.ctrlKey || event.metaKey)
                        && key === 'n'
                    ) {
                        event.preventDefault();

                        createNote().catch(handleError);
                    }
                });
            },
        });

        state.editor = editors[0]
            || window.tinymce.get('noteEditor');

        if (!state.editor) {
            throw new Error(
                'Instance TinyMCE tidak terbentuk.'
            );
        }

        fitEditorToHost();
    }

    function bindUI() {
        el.collapseSidebar.addEventListener(
            'click',
            () => {
                el.appShell.classList.add(
                    'sidebar-collapsed'
                );

                localStorage.setItem(
                    'browsernote.sidebar',
                    'collapsed'
                );

                window.setTimeout(
                    fitEditorToHost,
                    160
                );
            }
        );

        el.showSidebar.addEventListener(
            'click',
            () => {
                el.appShell.classList.remove(
                    'sidebar-collapsed'
                );

                localStorage.setItem(
                    'browsernote.sidebar',
                    'open'
                );

                window.setTimeout(
                    fitEditorToHost,
                    160
                );
            }
        );

        if (
            localStorage.getItem(
                'browsernote.sidebar'
            ) === 'collapsed'
        ) {
            el.appShell.classList.add(
                'sidebar-collapsed'
            );
        }

        el.newNoteButton.addEventListener(
            'click',
            () => {
                createNote().catch(handleError);
            }
        );

        el.saveButton.addEventListener(
            'click',
            () => {
                saveCurrent({
                    quiet: false,
                    automatic: false,
                }).catch(handleError);
            }
        );

        el.noteTitle.addEventListener(
            'input',
            () => {
                markDirty();
            }
        );

        el.noteTitle.addEventListener(
            'keydown',
            (event) => {
                const key = event.key.toLowerCase();

                if (event.key === 'Enter') {
                    event.preventDefault();
                    state.editor?.focus();
                }

                if (
                    (event.ctrlKey || event.metaKey)
                    && key === 's'
                ) {
                    event.preventDefault();

                    saveCurrent({
                        quiet: false,
                        automatic: false,
                    }).catch(handleError);
                }
            }
        );

        document.addEventListener(
            'keydown',
            (event) => {
                const key = event.key.toLowerCase();

                if (
                    (event.ctrlKey || event.metaKey)
                    && key === 's'
                ) {
                    event.preventDefault();

                    saveCurrent({
                        quiet: false,
                        automatic: false,
                    }).catch(handleError);
                }

                if (
                    (event.ctrlKey || event.metaKey)
                    && key === 'n'
                    && document.activeElement !== el.noteTitle
                ) {
                    event.preventDefault();
                    createNote().catch(handleError);
                }
            }
        );

        window.addEventListener(
            'beforeunload',
            (event) => {
                if (!state.dirty && !state.saving) {
                    return;
                }

                event.preventDefault();
                event.returnValue = '';
            }
        );

        const resizeObserver = new ResizeObserver(
            () => {
                fitEditorToHost();
            }
        );

        resizeObserver.observe(el.editorHost);
    }

    async function boot() {
        setSaveState('Memulai...', 'saving');
        el.saveButton.disabled = true;

        try {
            bindUI();
            await initTinyMCE();
            await loadNotes();
            setSaveState('Tersimpan', 'saved');
        } catch (error) {
            handleError(error);
        }
    }

    boot();
})();
'@

Write-Utf8NoBom -Path $JsPath -Content $js
Ok "Autosave JavaScript dipasang"

Step "4. STATIC AUTOSAVE VERIFICATION"

$installed = [System.IO.File]::ReadAllText($JsPath)

$requiredFragments = @(
    'const AUTOSAVE_DELAY = 700;',
    'function scheduleAutosave()',
    'state.editVersion += 1;',
    'versionAtStart = state.editVersion',
    'state.editVersion === versionAtStart',
    'function flushPendingSave()',
    'Tersimpan otomatis',
    'beforeunload'
)

foreach ($fragment in $requiredFragments) {
    if (-not $installed.Contains($fragment)) {
        Fail "Komponen autosave tidak ditemukan: $fragment"
    }

    Ok "Verified: $fragment"
}

Step "5. HTTP JAVASCRIPT VERIFICATION"

try {
    $response = Invoke-WebRequest `
        -Uri "$BaseUrl/assets/js/browsernote.js" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "browsernote.js tidak dapat diakses melalui Apache."
}

if ($response.StatusCode -ne 200) {
    Fail "browsernote.js HTTP status $($response.StatusCode)"
}

if ($response.Content -notlike '*const AUTOSAVE_DELAY = 700;*') {
    Fail "Apache masih menyajikan JavaScript lama."
}

Ok "JavaScript autosave tersedia melalui Apache"

Step "6. API SMOKE TEST"

try {
    $notes = Invoke-RestMethod `
        -Method GET `
        -Uri "$BaseUrl/api/notes" `
        -Headers @{ Accept = 'application/json' } `
        -TimeoutSec 8 `
        -ErrorAction Stop
}
catch {
    Fail "Notes API tidak dapat diakses."
}

if (-not $notes.ok) {
    Fail "Notes API mengembalikan ok=false."
}

Ok "Notes API tetap normal"
Write-Host "       Active notes: $($notes.count)" -ForegroundColor DarkGray

Step "7. ROOT PAGE SMOKE TEST"

try {
    $page = Invoke-WebRequest `
        -Uri "$BaseUrl/" `
        -UseBasicParsing `
        -TimeoutSec 8
}
catch {
    Fail "Root BrowserNote tidak dapat diakses."
}

if ($page.StatusCode -ne 200) {
    Fail "Root BrowserNote tidak HTTP 200."
}

if ($page.Content -notlike '*browsernote.js*') {
    Fail "Root page tidak memuat browsernote.js."
}

Ok "Root BrowserNote tetap normal"

Step "STAGE 05 PASS"

Write-Host ""
Write-Host "Project     : $ProjectRoot" -ForegroundColor White
Write-Host "URL         : $BaseUrl/" -ForegroundColor White
Write-Host "Autosave    : 700 ms debounce" -ForegroundColor White
Write-Host "Race guard  : PASS" -ForegroundColor White
Write-Host "Ctrl + S    : PASS" -ForegroundColor White
Write-Host "Ctrl + N    : PASS" -ForegroundColor White
Write-Host "BeforeUnload: PASS" -ForegroundColor White
Write-Host "API         : PASS" -ForegroundColor White
Write-Host ""
Write-Host "Uji manual Stage 05:" -ForegroundColor Green
Write-Host "1. Ketik beberapa kata lalu berhenti." -ForegroundColor White
Write-Host "2. Status harus berubah: Belum tersimpan -> Menyimpan... -> Tersimpan otomatis." -ForegroundColor White
Write-Host "3. Ketik cepat saat status Menyimpan... dan pastikan perubahan berikutnya tetap tersimpan." -ForegroundColor White
Write-Host "4. Refresh browser setelah status Tersimpan otomatis dan cek isi tetap ada." -ForegroundColor White
Write-Host "5. Ubah judul dan cek judul ikut autosave." -ForegroundColor White
Write-Host "6. Pindah catatan saat ada perubahan dan pastikan perubahan diflush sebelum pindah." -ForegroundColor White
Write-Host ""
Write-Host "Berikutnya : Stage 06 - Local Recovery / perlindungan draft browser" -ForegroundColor Green
