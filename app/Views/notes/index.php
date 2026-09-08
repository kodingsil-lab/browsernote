<!doctype html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <title>BrowserNote</title>
    <link rel="stylesheet" href="<?= base_url('assets/css/app.css') ?>">
<link rel="stylesheet" href="<?= base_url('assets/css/ui-polish-fix.css') ?>">
<link rel="stylesheet" href="<?= base_url('assets/css/ui-layout-scale-fix.css') ?>">
</head>
<body>
<div class="app-shell" id="appShell">
    <aside class="sidebar" id="sidebar">
        <div class="brand-row">
            <div class="brand-wrap">
                <div class="brand-mark">N</div>
                <div>
                    <div class="brand">BrowserNote</div>
                    <div class="brand-subtitle">local notes</div>
                </div>
            </div>

            <button
                class="icon-button"
                id="collapseSidebar"
                type="button"
                aria-label="Ciutkan sidebar"
                title="Ciutkan sidebar"
            >‹</button>
        </div>

        <button class="new-note-button" id="newNoteButton" type="button">
            <span>＋</span>
            <span>Catatan Baru</span>
        </button>

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

        <section class="sidebar-section notes-section">
            <div class="section-heading">
                <span id="noteListHeading">CATATAN</span>
                <span class="section-count" id="noteCount">0</span>
            </div>

            <div class="note-list" id="noteList">
                <div class="sidebar-empty">Memuat catatan...</div>
            </div>
        </section>

        <section class="sidebar-section folders-section" id="foldersSection">
            <div class="section-heading">
                <span>FOLDER</span>

                <button
                    class="section-add-button"
                    id="addFolderButton"
                    type="button"
                    title="Buat folder"
                    aria-label="Buat folder"
                >＋</button>
            </div>

            <div class="folder-list" id="folderList">
                <button
                    class="folder-item active"
                    id="allNotesFolder"
                    type="button"
                    data-folder-filter="all"
                >
                    <span class="folder-name">Semua Catatan</span>
                    <span class="folder-count" id="allNotesCount">0</span>
                </button>

                <button
                    class="folder-item"
                    id="unfiledFolder"
                    type="button"
                    data-folder-filter="unfiled"
                >
                    <span class="folder-name">Tanpa Folder</span>
                    <span class="folder-count" id="unfiledCount">0</span>
                </button>

                <div id="dynamicFolderList"></div>
            </div>
        </section>

        <div class="sidebar-footer">
            <button class="nav-item status-nav-item" id="archiveNavButton" type="button">
                <span class="nav-icon">◇</span>
                <span class="status-nav-label">Arsip</span>
                <span class="status-nav-count" id="archiveCount">0</span>
            </button>

            <button class="nav-item status-nav-item" id="trashNavButton" type="button">
                <span class="nav-icon">×</span>
                <span class="status-nav-label">Sampah</span>
                <span class="status-nav-count" id="trashCount">0</span>
            </button>
        </div>
    </aside>

    <main class="workspace">
        <header class="topbar">
            <button
                class="show-sidebar-button"
                id="showSidebar"
                type="button"
                aria-label="Tampilkan sidebar"
                title="Tampilkan sidebar"
            >☰</button>

            <input
                class="note-title"
                id="noteTitle"
                value=""
                placeholder="Catatan tanpa judul"
                maxlength="255"
                autocomplete="off"
                aria-label="Judul catatan"
            >

            <span class="note-status-badge" id="noteStatusBadge">Aktif</span>

            <label class="folder-select-wrap" id="folderSelectWrap" title="Pindahkan catatan ke folder">
                <span class="folder-select-label">Folder</span>
                <select id="noteFolderSelect" class="folder-select" aria-label="Folder catatan">
                    <option value="">Tanpa Folder</option>
                </select>
            </label>

            <div class="note-actions" id="noteActions">
                <button class="note-action-button" id="archiveAction" type="button">Arsipkan</button>
                <button class="note-action-button danger-soft" id="trashAction" type="button">Sampah</button>
                <button class="note-action-button" id="restoreAction" type="button" hidden>Pulihkan</button>
                <button class="note-action-button danger" id="forceDeleteAction" type="button" hidden>Hapus Permanen</button>
            </div>

            <div class="save-state" id="saveState" data-state="ready">
                Siap
            </div>

            <button class="save-button" id="saveButton" type="button">
                Simpan
            </button>
        </header>

        <section class="editor-host" id="editorHost">
            <textarea id="noteEditor" aria-label="Isi catatan"></textarea>
        </section>

        <footer class="statusbar">
            <div class="status-left">
                <span id="currentNoteInfo">Belum ada catatan aktif</span>
            </div>

            <div class="status-right">
                <span id="wordCount">0 kata</span>
                <span class="status-separator">•</span>
                <span id="charCount">0 karakter</span>
                <span class="status-separator">•</span>
                <span>TinyMCE lokal</span>
            </div>
        </footer>
    </main>
</div>

<div class="folder-menu" id="folderMenu" hidden>
    <button type="button" id="renameFolderAction">Ganti nama</button>
    <button type="button" id="deleteFolderAction" class="danger">Hapus folder</button>
</div>

<div class="toast" id="toast" role="status" aria-live="polite"></div>

<script>
window.BrowserNoteConfig = {
    baseUrl: <?= json_encode(rtrim(base_url(), '/'), JSON_UNESCAPED_SLASHES) ?>,
    tinyMceBase: <?= json_encode(rtrim(base_url('assets/vendor/tinymce'), '/'), JSON_UNESCAPED_SLASHES) ?>
};
</script>

<script src="<?= base_url('assets/vendor/tinymce/tinymce.min.js') ?>"></script>
<script src="<?= base_url('assets/js/browsernote.js') ?>"></script>
<script src="<?= base_url('assets/js/search.js') ?>"></script>
<script src="<?= base_url('assets/js/shortcuts.js') ?>"></script>
<script src="<?= base_url('assets/js/export.js') ?>"></script>
<script src="<?= base_url('assets/js/polish.js') ?>"></script>
<script src="<?= base_url('assets/js/editor-polish-fix.js') ?>"></script>
</body>
</html>