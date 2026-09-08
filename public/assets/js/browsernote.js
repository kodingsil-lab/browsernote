(() => {
    'use strict';

    const config = window.BrowserNoteConfig || {};
    const apiBase = `${config.baseUrl}/api/notes`;
    const folderApiBase = `${config.baseUrl}/api/folders`;

    const AUTOSAVE_DELAY = 700;
    const LOCAL_DRAFT_DELAY = 180;
    const DRAFT_PREFIX = 'browsernote.draft.v1.';

    const state = {
        editor: null,

        collections: {
            active: [],
            archived: [],
            trash: [],
        },

        folders: [],

        mode: 'active',
        folderFilter: 'all',

        currentId: null,
        currentNote: null,
        folderMenuId: null,

        dirty: false,
        loading: false,
        saving: false,

        editVersion: 0,
        lastSavedVersion: 0,
        savePromise: null,
        autosaveTimer: null,

        localDraftTimer: null,
        localDraftErrorShown: false,

        toastTimer: null,
    };

    const el = {
        appShell: document.getElementById('appShell'),
        workspace: document.querySelector('.workspace'),
        collapseSidebar: document.getElementById('collapseSidebar'),
        showSidebar: document.getElementById('showSidebar'),

        newNoteButton: document.getElementById('newNoteButton'),
        noteListHeading: document.getElementById('noteListHeading'),
        noteList: document.getElementById('noteList'),
        noteCount: document.getElementById('noteCount'),

        foldersSection: document.getElementById('foldersSection'),
        allNotesFolder: document.getElementById('allNotesFolder'),
        allNotesCount: document.getElementById('allNotesCount'),
        unfiledFolder: document.getElementById('unfiledFolder'),
        unfiledCount: document.getElementById('unfiledCount'),
        dynamicFolderList: document.getElementById('dynamicFolderList'),
        addFolderButton: document.getElementById('addFolderButton'),

        archiveNavButton: document.getElementById('archiveNavButton'),
        archiveCount: document.getElementById('archiveCount'),
        trashNavButton: document.getElementById('trashNavButton'),
        trashCount: document.getElementById('trashCount'),

        noteTitle: document.getElementById('noteTitle'),
        noteStatusBadge: document.getElementById('noteStatusBadge'),
        folderSelectWrap: document.getElementById('folderSelectWrap'),
        noteFolderSelect: document.getElementById('noteFolderSelect'),

        archiveAction: document.getElementById('archiveAction'),
        trashAction: document.getElementById('trashAction'),
        restoreAction: document.getElementById('restoreAction'),
        forceDeleteAction: document.getElementById('forceDeleteAction'),

        saveState: document.getElementById('saveState'),
        saveButton: document.getElementById('saveButton'),

        editorHost: document.getElementById('editorHost'),
        currentNoteInfo: document.getElementById('currentNoteInfo'),

        wordCount: document.getElementById('wordCount'),
        charCount: document.getElementById('charCount'),

        folderMenu: document.getElementById('folderMenu'),
        renameFolderAction: document.getElementById('renameFolderAction'),
        deleteFolderAction: document.getElementById('deleteFolderAction'),

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

    function showToast(message, duration = 2200) {
        el.toast.textContent = message;
        el.toast.classList.add('show');

        window.clearTimeout(state.toastTimer);
        state.toastTimer = window.setTimeout(() => {
            el.toast.classList.remove('show');
        }, duration);
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

    function modeStatusQuery(mode = state.mode) {
        if (mode === 'archived') {
            return 'archived';
        }

        if (mode === 'trash') {
            return 'trash';
        }

        return 'active';
    }

    function currentCollection() {
        return state.collections[state.mode] || [];
    }

    function isTrashMode() {
        return state.mode === 'trash';
    }

    function canEditCurrent() {
        return Boolean(state.currentId) && !isTrashMode();
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

    /*
     * LOCAL RECOVERY
     */

    function draftKey(noteId) {
        return `${DRAFT_PREFIX}${Number(noteId)}`;
    }

    function readLocalDraft(noteId) {
        if (!noteId) {
            return null;
        }

        try {
            const raw = localStorage.getItem(draftKey(noteId));

            if (!raw) {
                return null;
            }

            const draft = JSON.parse(raw);

            if (
                !draft
                || Number(draft.noteId) !== Number(noteId)
                || typeof draft.title !== 'string'
                || typeof draft.content !== 'string'
            ) {
                localStorage.removeItem(draftKey(noteId));
                return null;
            }

            return draft;
        } catch (error) {
            console.warn('Local draft read failed', error);
            return null;
        }
    }

    function clearLocalDraft(noteId) {
        if (!noteId) {
            return;
        }

        try {
            localStorage.removeItem(draftKey(noteId));
        } catch (error) {
            console.warn('Local draft cleanup failed', error);
        }
    }

    function persistLocalDraftNow() {
        if (
            state.loading
            || !state.currentId
            || !state.editor
            || !state.dirty
            || isTrashMode()
        ) {
            return false;
        }

        const draft = {
            version: 1,
            noteId: Number(state.currentId),
            title: el.noteTitle.value || '',
            content: state.editor.getContent(),
            folderId: el.noteFolderSelect.value || null,
            editVersion: state.editVersion,
            baseUpdatedAt: state.currentNote?.updated_at || null,
            savedAt: Date.now(),
        };

        try {
            localStorage.setItem(
                draftKey(state.currentId),
                JSON.stringify(draft)
            );

            state.localDraftErrorShown = false;
            return true;
        } catch (error) {
            console.error('Local draft write failed', error);

            if (!state.localDraftErrorShown) {
                state.localDraftErrorShown = true;
                showToast(
                    'Draft lokal gagal disimpan. Periksa penyimpanan browser.',
                    4200
                );
            }

            return false;
        }
    }

    function clearLocalDraftTimer() {
        if (state.localDraftTimer !== null) {
            window.clearTimeout(state.localDraftTimer);
            state.localDraftTimer = null;
        }
    }

    function scheduleLocalDraft() {
        clearLocalDraftTimer();

        if (
            state.loading
            || !state.currentId
            || !state.editor
            || !state.dirty
            || isTrashMode()
        ) {
            return;
        }

        state.localDraftTimer = window.setTimeout(() => {
            state.localDraftTimer = null;
            persistLocalDraftNow();
        }, LOCAL_DRAFT_DELAY);
    }

    function localDraftMatchesServer(draft, note) {
        return (
            (draft.title || '') === (note.title || '')
            && (draft.content || '') === (note.content || '')
            && String(draft.folderId || '') === String(note.folder_id || '')
        );
    }

    function shouldRecoverDraft(draft, note) {
        if (!draft || isTrashMode()) {
            return false;
        }

        if (localDraftMatchesServer(draft, note)) {
            clearLocalDraft(note.id);
            return false;
        }

        if (
            draft.baseUpdatedAt
            && note.updated_at
            && draft.baseUpdatedAt === note.updated_at
        ) {
            return true;
        }

        if (!draft.baseUpdatedAt) {
            return true;
        }

        return window.confirm(
            'Ditemukan draft lokal yang belum tersimpan, tetapi versi server juga sudah berubah. ' +
            'Pilih OK untuk memulihkan draft lokal. Pilih Cancel untuk memakai versi server.'
        );
    }

    function applyRecoveredDraft(draft, note) {
        state.currentId = Number(note.id);
        state.currentNote = note;

        state.editVersion = Math.max(
            1,
            Number(draft.editVersion) || 1
        );
        state.lastSavedVersion = 0;
        state.dirty = true;

        el.noteTitle.value = draft.title || '';
        el.noteFolderSelect.value = draft.folderId
            ? String(draft.folderId)
            : '';

        state.editor.setContent(draft.content || '');
        state.editor.undoManager.clear();

        updateCounters();
        setSaveState('Draft lokal dipulihkan', 'dirty');
        el.saveButton.disabled = false;

        persistLocalDraftNow();
        scheduleAutosave();

        showToast(
            'Draft lokal yang belum tersimpan berhasil dipulihkan.',
            3600
        );
    }

    /*
     * AUTOSAVE
     */

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
            || isTrashMode()
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
        if (
            state.loading
            || !state.currentId
            || isTrashMode()
        ) {
            return;
        }

        state.editVersion += 1;
        state.dirty = true;

        setSaveState('Belum tersimpan', 'dirty');
        el.saveButton.disabled = false;

        updateCounters();
        scheduleLocalDraft();
        scheduleAutosave();
    }

    function setClean(savedText = 'Tersimpan') {
        state.dirty = false;
        state.lastSavedVersion = state.editVersion;

        clearLocalDraftTimer();
        clearLocalDraft(state.currentId);

        setSaveState(savedText, 'saved');
        el.saveButton.disabled = true;

        if (state.editor) {
            state.editor.setDirty(false);
        }
    }

    /*
     * COLLECTIONS + MODE
     */

    async function loadCollections() {
        const [active, archived, trash] = await Promise.all([
            request(`${apiBase}?status=active`),
            request(`${apiBase}?status=archived`),
            request(`${apiBase}?status=trash`),
        ]);

        state.collections.active = Array.isArray(active.data)
            ? active.data
            : [];

        state.collections.archived = Array.isArray(archived.data)
            ? archived.data
            : [];

        state.collections.trash = Array.isArray(trash.data)
            ? trash.data
            : [];

        updateStatusCounts();
    }

    function updateStatusCounts() {
        el.archiveCount.textContent = String(
            state.collections.archived.length
        );

        el.trashCount.textContent = String(
            state.collections.trash.length
        );

        el.allNotesCount.textContent = String(
            state.collections.active.length
        );

        const unfiled = state.collections.active.filter(
            (note) => !note.folder_id
        ).length;

        el.unfiledCount.textContent = String(unfiled);
    }

    function setEditorReadonly(readonly) {
        el.noteTitle.readOnly = readonly;
        el.noteFolderSelect.disabled = readonly;
        el.saveButton.hidden = readonly;

        el.workspace.classList.toggle(
            'readonly-trash',
            readonly
        );

        if (state.editor?.mode?.set) {
            state.editor.mode.set(
                readonly ? 'readonly' : 'design'
            );
        }
    }

    function updateModeUI() {
        const archived = state.mode === 'archived';
        const trash = state.mode === 'trash';
        const active = state.mode === 'active';

        el.archiveNavButton.classList.toggle('active', archived);
        el.trashNavButton.classList.toggle('active', trash);

        el.foldersSection.hidden = !active;
        el.addFolderButton.disabled = !active;
        el.newNoteButton.disabled = !active;

        el.noteListHeading.textContent = active
            ? 'CATATAN'
            : archived
                ? 'ARSIP'
                : 'SAMPAH';

        el.noteStatusBadge.textContent = active
            ? 'Aktif'
            : archived
                ? 'Arsip'
                : 'Sampah';

        el.noteStatusBadge.className = 'note-status-badge';

        if (archived) {
            el.noteStatusBadge.classList.add('archived');
        }

        if (trash) {
            el.noteStatusBadge.classList.add('trashed');
        }

        el.archiveAction.hidden = !active;
        el.trashAction.hidden = trash;
        el.restoreAction.hidden = active;
        el.forceDeleteAction.hidden = !trash;

        setEditorReadonly(trash);

        if (trash) {
            setSaveState('Read-only', 'ready');
        }

        setActiveFolderButton();
    }

    async function switchMode(mode) {
        if (!['active', 'archived', 'trash'].includes(mode)) {
            return;
        }

        if (state.mode === mode) {
            return;
        }

        await flushPendingSave();

        state.mode = mode;
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        const list = currentVisibleNotes();

        if (list.length > 0) {
            await openNote(Number(list[0].id));
        } else {
            clearCurrentEditor();
        }
    }

    function clearCurrentEditor() {
        clearAutosaveTimer();
        clearLocalDraftTimer();

        state.currentId = null;
        state.currentNote = null;
        state.dirty = false;

        el.noteTitle.value = '';
        el.noteFolderSelect.value = '';
        el.currentNoteInfo.textContent = 'Tidak ada catatan';

        if (state.editor) {
            state.editor.setContent('');
            state.editor.undoManager.clear();
        }

        el.wordCount.textContent = '0 kata';
        el.charCount.textContent = '0 karakter';
        el.saveButton.disabled = true;

        updateModeUI();
    }

    /*
     * FOLDERS
     */

    function folderNameById(folderId) {
        if (!folderId) {
            return 'Tanpa Folder';
        }

        const folder = state.folders.find(
            (item) => Number(item.id) === Number(folderId)
        );

        return folder?.name || 'Tanpa Folder';
    }

    function renderFolderSelect() {
        const currentValue = state.currentNote?.folder_id
            ? String(state.currentNote.folder_id)
            : '';

        el.noteFolderSelect.innerHTML = '';

        const none = document.createElement('option');
        none.value = '';
        none.textContent = 'Tanpa Folder';
        el.noteFolderSelect.appendChild(none);

        for (const folder of state.folders) {
            const option = document.createElement('option');
            option.value = String(folder.id);
            option.textContent = folder.name;
            el.noteFolderSelect.appendChild(option);
        }

        el.noteFolderSelect.value = currentValue;
    }

    function setActiveFolderButton() {
        document
            .querySelectorAll('[data-folder-filter]')
            .forEach((button) => {
                button.classList.toggle(
                    'active',
                    state.mode === 'active'
                    && String(button.dataset.folderFilter)
                        === String(state.folderFilter)
                );
            });
    }

    function renderFolders() {
        el.dynamicFolderList.innerHTML = '';

        for (const folder of state.folders) {
            const row = document.createElement('div');
            row.className = 'folder-item-row';

            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'folder-item';
            button.dataset.folderFilter = String(folder.id);

            const name = document.createElement('span');
            name.className = 'folder-name';
            name.textContent = folder.name;

            const count = document.createElement('span');
            count.className = 'folder-count';
            count.textContent = String(
                state.collections.active.filter(
                    (note) => Number(note.folder_id) === Number(folder.id)
                ).length
            );

            button.append(name, count);

            button.addEventListener('click', async () => {
                try {
                    if (state.mode !== 'active') {
                        await switchMode('active');
                    }

                    state.folderFilter = String(folder.id);
                    setActiveFolderButton();
                    renderNotes();

                    const list = currentVisibleNotes();

                    if (
                        state.currentId
                        && list.some(
                            (note) => Number(note.id) === Number(state.currentId)
                        )
                    ) {
                        return;
                    }

                    if (list.length > 0) {
                        await openNote(Number(list[0].id));
                    } else {
                        clearCurrentEditor();
                    }
                } catch (error) {
                    handleError(error);
                }
            });

            const more = document.createElement('button');
            more.type = 'button';
            more.className = 'folder-more';
            more.textContent = '⋯';
            more.title = `Kelola ${folder.name}`;

            more.addEventListener('click', (event) => {
                event.stopPropagation();
                openFolderMenu(folder.id, more);
            });

            row.append(button, more);
            el.dynamicFolderList.appendChild(row);
        }

        updateStatusCounts();
        setActiveFolderButton();
        renderFolderSelect();
    }

    async function loadFolders() {
        const response = await request(folderApiBase);
        state.folders = Array.isArray(response.data)
            ? response.data
            : [];

        renderFolders();
    }

    async function createFolder() {
        const name = window.prompt('Nama folder baru');

        if (name === null) {
            return;
        }

        const clean = name.trim();

        if (!clean) {
            showToast('Nama folder tidak boleh kosong');
            return;
        }

        const response = await request(folderApiBase, {
            method: 'POST',
            body: JSON.stringify({ name: clean }),
        });

        await loadFolders();

        state.mode = 'active';
        state.folderFilter = String(response.data.id);

        updateModeUI();
        renderFolders();
        renderNotes();

        showToast('Folder dibuat');
    }

    function openFolderMenu(folderId, anchor) {
        state.folderMenuId = Number(folderId);

        const rect = anchor.getBoundingClientRect();
        el.folderMenu.hidden = false;

        const width = 150;
        const left = Math.max(
            8,
            Math.min(
                window.innerWidth - width - 8,
                rect.right - width
            )
        );

        const top = Math.min(
            window.innerHeight - 90,
            rect.bottom + 4
        );

        el.folderMenu.style.left = `${left}px`;
        el.folderMenu.style.top = `${top}px`;
    }

    function closeFolderMenu() {
        el.folderMenu.hidden = true;
        state.folderMenuId = null;
    }

    async function renameFolder(folderId) {
        const folder = state.folders.find(
            (item) => Number(item.id) === Number(folderId)
        );

        if (!folder) {
            return;
        }

        const name = window.prompt(
            'Nama folder',
            folder.name
        );

        if (name === null) {
            return;
        }

        const clean = name.trim();

        if (!clean) {
            showToast('Nama folder tidak boleh kosong');
            return;
        }

        await request(`${folderApiBase}/${folderId}`, {
            method: 'PATCH',
            body: JSON.stringify({ name: clean }),
        });

        await Promise.all([
            loadFolders(),
            loadCollections(),
        ]);

        renderFolders();
        renderNotes();

        showToast('Nama folder diperbarui');
    }

    async function deleteFolder(folderId) {
        const folder = state.folders.find(
            (item) => Number(item.id) === Number(folderId)
        );

        if (!folder) {
            return;
        }

        const confirmed = window.confirm(
            `Hapus folder "${folder.name}"?\n\nCatatan di dalam folder tidak akan dihapus. Catatan akan dipindahkan ke Tanpa Folder.`
        );

        if (!confirmed) {
            return;
        }

        await flushPendingSave();

        await request(`${folderApiBase}/${folderId}`, {
            method: 'DELETE',
        });

        if (String(state.folderFilter) === String(folderId)) {
            state.folderFilter = 'all';
        }

        await Promise.all([
            loadFolders(),
            loadCollections(),
        ]);

        if (state.currentId) {
            const refreshed = state.collections.active.find(
                (note) => Number(note.id) === Number(state.currentId)
            );

            if (refreshed) {
                state.currentNote = {
                    ...state.currentNote,
                    ...refreshed,
                };
            }
        }

        renderFolders();
        renderNotes();

        showToast('Folder dihapus');
    }

    /*
     * NOTES
     */

    function currentVisibleNotes() {
        const collection = currentCollection();

        if (state.mode !== 'active') {
            return collection;
        }

        if (state.folderFilter === 'all') {
            return collection;
        }

        if (state.folderFilter === 'unfiled') {
            return collection.filter(
                (note) => !note.folder_id
            );
        }

        const folderId = Number(state.folderFilter);

        return collection.filter(
            (note) => Number(note.folder_id) === folderId
        );
    }

    function renderNotes() {
        const visibleNotes = currentVisibleNotes();

        el.noteList.innerHTML = '';
        el.noteCount.textContent = String(visibleNotes.length);

        if (visibleNotes.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'mode-empty';

            empty.textContent = state.mode === 'active'
                ? 'Tidak ada catatan pada bagian ini.'
                : state.mode === 'archived'
                    ? 'Belum ada catatan di Arsip.'
                    : 'Sampah kosong.';

            el.noteList.appendChild(empty);
            return;
        }

        for (const note of visibleNotes) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'note-item';

            if (Number(note.id) === Number(state.currentId)) {
                button.classList.add('active');
            }

            const title = document.createElement('div');
            title.className = 'note-item-title';
            title.textContent = note.title || 'Catatan tanpa judul';

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

    async function openNote(id) {
        if (!state.editor) {
            return;
        }

        clearAutosaveTimer();
        clearLocalDraftTimer();

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

            renderFolderSelect();

            const localDraft = isTrashMode()
                ? null
                : readLocalDraft(note.id);

            if (
                localDraft
                && shouldRecoverDraft(localDraft, note)
            ) {
                applyRecoveredDraft(localDraft, note);
            } else {
                if (localDraft) {
                    clearLocalDraft(note.id);
                }

                el.noteTitle.value = note.title || '';
                el.noteFolderSelect.value = note.folder_id
                    ? String(note.folder_id)
                    : '';

                state.editor.setContent(note.content || '');
                state.editor.undoManager.clear();

                updateCounters();

                if (!isTrashMode()) {
                    setClean('Tersimpan');
                }
            }

            el.currentNoteInfo.textContent =
                `#${note.id} · ${folderNameById(note.folder_id)}`;

            updateModeUI();
            renderNotes();

            window.setTimeout(() => {
                state.editor.focus();
            }, 0);
        } finally {
            state.loading = false;
        }
    }

    async function createNote() {
        if (state.mode !== 'active') {
            await switchMode('active');
        }

        await flushPendingSave();

        el.newNoteButton.disabled = true;
        setSaveState('Membuat...', 'saving');

        let folderId = null;

        if (
            state.folderFilter !== 'all'
            && state.folderFilter !== 'unfiled'
        ) {
            folderId = Number(state.folderFilter);
        }

        try {
            const response = await request(apiBase, {
                method: 'POST',
                body: JSON.stringify({
                    title: 'Catatan tanpa judul',
                    content: '<p></p>',
                    folder_id: folderId,
                }),
            });

            await loadCollections();
            await loadFolders();

            renderFolders();
            renderNotes();

            await openNote(Number(response.data.id));

            showToast('Catatan baru dibuat');

            return response.data;
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
            || isTrashMode()
        ) {
            return;
        }

        clearLocalDraftTimer();
        persistLocalDraftNow();

        const noteId = Number(state.currentId);
        const versionAtStart = state.editVersion;

        const title = el.noteTitle.value.trim()
            || 'Catatan tanpa judul';

        const content = state.editor.getContent();

        const folderId = el.noteFolderSelect.value
            ? Number(el.noteFolderSelect.value)
            : null;

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
                        folder_id: folderId,
                    }),
                }
            );

            if (Number(state.currentId) !== noteId) {
                return;
            }

            state.currentNote = response.data;

            await loadCollections();
            await loadFolders();

            renderFolders();
            renderNotes();

            el.currentNoteInfo.textContent =
                `#${response.data.id} · ${folderNameById(response.data.folder_id)}`;

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

                persistLocalDraftNow();
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

                persistLocalDraftNow();

                setSaveState(
                    'Gagal menyimpan · draft lokal aman',
                    'error'
                );
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
        clearLocalDraftTimer();

        if (isTrashMode()) {
            return;
        }

        if (state.dirty) {
            persistLocalDraftNow();
        }

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

    /*
     * ARCHIVE + TRASH ACTIONS
     */

    async function archiveCurrent() {
        if (!state.currentId || state.mode !== 'active') {
            return;
        }

        await flushPendingSave();

        const id = Number(state.currentId);

        await request(`${apiBase}/${id}/archive`, {
            method: 'POST',
        });

        clearLocalDraft(id);

        await loadCollections();

        state.mode = 'archived';
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(id);

        showToast('Catatan diarsipkan');
    }

    async function moveCurrentToTrash() {
        if (!state.currentId || state.mode === 'trash') {
            return;
        }

        await flushPendingSave();

        const id = Number(state.currentId);

        await request(`${apiBase}/${id}`, {
            method: 'DELETE',
        });

        clearLocalDraft(id);

        await loadCollections();

        state.mode = 'trash';
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(id);

        showToast('Catatan dipindahkan ke Sampah');
    }

    async function restoreCurrent() {
        if (!state.currentId) {
            return;
        }

        const id = Number(state.currentId);

        if (state.mode === 'archived') {
            await flushPendingSave();

            await request(
                `${apiBase}/${id}/restore-archive`,
                { method: 'POST' }
            );
        } else if (state.mode === 'trash') {
            await request(
                `${apiBase}/${id}/restore-trash`,
                { method: 'POST' }
            );
        } else {
            return;
        }

        clearLocalDraft(id);

        await loadCollections();

        state.mode = 'active';
        state.folderFilter = 'all';

        updateModeUI();
        renderFolders();
        renderNotes();

        await openNote(id);

        showToast('Catatan dipulihkan');
    }

    async function forceDeleteCurrent() {
        if (
            !state.currentId
            || state.mode !== 'trash'
        ) {
            return;
        }

        const id = Number(state.currentId);
        const title = state.currentNote?.title
            || 'Catatan tanpa judul';

        const confirmed = window.confirm(
            `Hapus permanen "${title}"?\n\nTindakan ini tidak dapat dibatalkan.`
        );

        if (!confirmed) {
            return;
        }

        await request(
            `${apiBase}/${id}/force`,
            { method: 'DELETE' }
        );

        clearLocalDraft(id);

        await loadCollections();

        renderNotes();
        updateStatusCounts();

        const remaining = currentVisibleNotes();

        if (remaining.length > 0) {
            await openNote(Number(remaining[0].id));
        } else {
            clearCurrentEditor();
        }

        showToast('Catatan dihapus permanen');
    }

    function handleError(error) {
        console.error(error);

        if (state.dirty && !isTrashMode()) {
            persistLocalDraftNow();

            setSaveState(
                'Gagal menyimpan · draft lokal aman',
                'error'
            );
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
            throw new Error('TinyMCE lokal gagal dimuat.');
        }

        const editors = await window.tinymce.init({
            selector: '#noteEditor',
            base_url: config.tinyMceBase,
            suffix: '.min',
            license_key: 'gpl',
            // BROWSERNOTE_STAGE12_TINYMCE_START
            promotion: false,
            branding: false,
            block_formats: 'Paragraf=p; Judul 1=h1; Judul 2=h2; Judul 3=h3; Judul 4=h4',
            font_size_formats: '12px 13px 14px 15px 16px 18px 20px 22px 24px 28px 32px',
            font_family_formats: 'Segoe UI=Segoe UI,Arial,sans-serif; Arial=Arial,Helvetica,sans-serif; Georgia=Georgia,serif; Times New Roman=Times New Roman,Times,serif; Consolas=Consolas,Cascadia Code,Courier New,monospace',
            // BROWSERNOTE_STAGE12_TINYMCE_END

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
                'undo redo | blocks',
                'bold italic underline strikethrough | forecolor backcolor',
                'alignleft aligncenter alignright | bullist numlist',
                'outdent indent | blockquote link',
                'codesample table | removeformat',
                'searchreplace code fullscreen'
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
                    window.BrowserNoteAppearance?.attach(editor);
                    fitEditorToHost();
                    updateCounters();
                });

                editor.on('input change undo redo', () => {
                    markDirty();
                });

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
            throw new Error('Instance TinyMCE tidak terbentuk.');
        }

        fitEditorToHost();
    }

    function bindUI() {
        el.collapseSidebar.addEventListener('click', () => {
            el.appShell.classList.add('sidebar-collapsed');
            localStorage.setItem('browsernote.sidebar', 'collapsed');
            window.setTimeout(fitEditorToHost, 160);
        });

        el.showSidebar.addEventListener('click', () => {
            el.appShell.classList.remove('sidebar-collapsed');
            localStorage.setItem('browsernote.sidebar', 'open');
            window.setTimeout(fitEditorToHost, 160);
        });

        if (
            localStorage.getItem('browsernote.sidebar')
            === 'collapsed'
        ) {
            el.appShell.classList.add('sidebar-collapsed');
        }

        el.newNoteButton.addEventListener('click', () => {
            createNote().catch(handleError);
        });

        el.saveButton.addEventListener('click', () => {
            saveCurrent({
                quiet: false,
                automatic: false,
            }).catch(handleError);
        });

        el.noteTitle.addEventListener('input', markDirty);
        el.noteFolderSelect.addEventListener('change', markDirty);

        el.noteTitle.addEventListener('keydown', (event) => {
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
        });

        el.addFolderButton.addEventListener('click', () => {
            createFolder().catch(handleError);
        });

        el.allNotesFolder.addEventListener('click', async () => {
            try {
                if (state.mode !== 'active') {
                    await switchMode('active');
                }

                state.folderFilter = 'all';
                setActiveFolderButton();
                renderNotes();

                const list = currentVisibleNotes();

                if (list.length > 0) {
                    await openNote(Number(list[0].id));
                } else {
                    clearCurrentEditor();
                }
            } catch (error) {
                handleError(error);
            }
        });

        el.unfiledFolder.addEventListener('click', async () => {
            try {
                if (state.mode !== 'active') {
                    await switchMode('active');
                }

                state.folderFilter = 'unfiled';
                setActiveFolderButton();
                renderNotes();

                const list = currentVisibleNotes();

                if (list.length > 0) {
                    await openNote(Number(list[0].id));
                } else {
                    clearCurrentEditor();
                }
            } catch (error) {
                handleError(error);
            }
        });

        el.archiveNavButton.addEventListener('click', () => {
            switchMode('archived').catch(handleError);
        });

        el.trashNavButton.addEventListener('click', () => {
            switchMode('trash').catch(handleError);
        });

        el.archiveAction.addEventListener('click', () => {
            archiveCurrent().catch(handleError);
        });

        el.trashAction.addEventListener('click', () => {
            moveCurrentToTrash().catch(handleError);
        });

        el.restoreAction.addEventListener('click', () => {
            restoreCurrent().catch(handleError);
        });

        el.forceDeleteAction.addEventListener('click', () => {
            forceDeleteCurrent().catch(handleError);
        });

        el.renameFolderAction.addEventListener('click', () => {
            const id = state.folderMenuId;
            closeFolderMenu();

            if (id) {
                renameFolder(id).catch(handleError);
            }
        });

        el.deleteFolderAction.addEventListener('click', () => {
            const id = state.folderMenuId;
            closeFolderMenu();

            if (id) {
                deleteFolder(id).catch(handleError);
            }
        });

        document.addEventListener('click', (event) => {
            if (
                !el.folderMenu.hidden
                && !el.folderMenu.contains(event.target)
            ) {
                closeFolderMenu();
            }
        });

        document.addEventListener('keydown', (event) => {
            const key = event.key.toLowerCase();

            if (event.key === 'Escape') {
                closeFolderMenu();
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

            if (
                (event.ctrlKey || event.metaKey)
                && key === 'n'
                && document.activeElement !== el.noteTitle
            ) {
                event.preventDefault();
                createNote().catch(handleError);
            }
        });

        window.addEventListener('beforeunload', (event) => {
            if (state.dirty && !isTrashMode()) {
                clearLocalDraftTimer();
                persistLocalDraftNow();
            }

            if (!state.dirty && !state.saving) {
                return;
            }

            event.preventDefault();
            event.returnValue = '';
        });

        window.addEventListener('pagehide', () => {
            if (state.dirty && !isTrashMode()) {
                clearLocalDraftTimer();
                persistLocalDraftNow();
            }
        });

        const resizeObserver = new ResizeObserver(() => {
            fitEditorToHost();
        });

        resizeObserver.observe(el.editorHost);
    }

    async function boot() {
        setSaveState('Memulai...', 'saving');
        el.saveButton.disabled = true;

        try {
            bindUI();
            await initTinyMCE();

            await Promise.all([
                loadCollections(),
                loadFolders(),
            ]);

            updateModeUI();
            renderFolders();
            renderNotes();

            if (state.collections.active.length > 0) {
                await openNote(
                    Number(state.collections.active[0].id)
                );
            } else {
                clearCurrentEditor();
            }

            if (!state.dirty) {
                setSaveState('Tersimpan', 'saved');
            }
        } catch (error) {
            handleError(error);
        }
    }

    window.BrowserNoteRecovery = {
        getCurrentDraft() {
            return readLocalDraft(state.currentId);
        },

        persistNow() {
            return persistLocalDraftNow();
        },

        clearCurrentDraft() {
            clearLocalDraft(state.currentId);
        },
    };

    window.BrowserNoteFolders = {
        reload() {
            return loadFolders();
        },

        getFolders() {
            return [...state.folders];
        },

        getFilter() {
            return state.folderFilter;
        },
    };

    window.BrowserNoteStatus = {
        getMode() {
            return state.mode;
        },

        getCounts() {
            return {
                active: state.collections.active.length,
                archived: state.collections.archived.length,
                trash: state.collections.trash.length,
            };
        },

        switchMode(mode) {
            return switchMode(mode);
        },
    };

    window.BrowserNoteBridge = {
        async openNoteById(id, mode = 'active') {
            await flushPendingSave();

            state.mode = mode === 'archived'
                ? 'archived'
                : 'active';

            state.folderFilter = 'all';

            updateModeUI();
            renderFolders();
            renderNotes();

            await openNote(Number(id));
        },

        refresh() {
            updateModeUI();
            renderFolders();
            renderNotes();
        },

        getMode() {
            return state.mode;
        },

        getCurrentId() {
            return state.currentId;
        },
    };

    boot();
})();