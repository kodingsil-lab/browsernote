<!doctype html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <meta name="theme-color" content="#20242a">
    <link rel="icon" type="image/svg+xml" href="<?= base_url('favicon.svg?v=1') ?>">
    <link rel="icon" type="image/png" sizes="32x32" href="<?= base_url('favicon-32x32.png?v=1') ?>">
    <link rel="shortcut icon" href="<?= base_url('favicon.ico?v=1') ?>">
    <link rel="apple-touch-icon" sizes="180x180" href="<?= base_url('apple-touch-icon.png?v=1') ?>">
    <title>BrowserNote</title>
    <link rel="stylesheet" href="<?= base_url('assets/css/app.css') ?>">
<link rel="stylesheet" href="<?= base_url('assets/css/ui-polish-fix.css') ?>">
<link rel="stylesheet" href="<?= base_url('assets/css/ui-layout-scale-fix.css') ?>">
<link rel="stylesheet" href="<?= base_url('assets/css/writing-preferences.css?v=5') ?>">
<link rel="stylesheet" href="<?= base_url('assets/css/tooltips.css?v=1') ?>">
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
                data-tooltip="Sembunyikan sidebar"
                data-tooltip-side="right"
            >‹</button>
        </div>

        <button class="new-note-button" id="newNoteButton" type="button" data-tooltip="Buat catatan baru (Ctrl+N)" data-tooltip-side="right">
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
                aria-label="Bersihkan pencarian"
                data-tooltip="Bersihkan pencarian"
                data-tooltip-side="left"
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
                    aria-label="Buat folder"
                    data-tooltip="Buat folder baru"
                    data-tooltip-side="left"
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
                data-tooltip="Tampilkan sidebar"
                data-tooltip-side="right"
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
                <button class="note-action-button" id="archiveAction" type="button" data-tooltip="Pindahkan catatan ke Arsip" data-tooltip-side="bottom">Arsipkan</button>
                <button class="note-action-button danger-soft" id="trashAction" type="button" data-tooltip="Pindahkan catatan ke Sampah" data-tooltip-side="bottom">Sampah</button>
                <button class="note-action-button" id="restoreAction" type="button" data-tooltip="Kembalikan catatan dari Arsip atau Sampah" data-tooltip-side="bottom" hidden>Pulihkan</button>
                <button class="note-action-button danger" id="forceDeleteAction" type="button" data-tooltip="Hapus catatan secara permanen" data-tooltip-side="bottom" hidden>Hapus Permanen</button>
            </div>

            <div class="writing-tools" aria-label="Pengaturan menulis">
                <button class="writing-button" id="focusModeButton" type="button" aria-pressed="false" data-tooltip="Tulis tanpa gangguan; tekan Esc untuk keluar" data-tooltip-side="bottom">Fokus</button>
                <button class="writing-button" id="appearanceButton" type="button" aria-haspopup="dialog" aria-controls="appearanceDialog" data-tooltip="Atur tema, lebar, huruf, dan jarak tulisan" data-tooltip-side="bottom">Tampilan</button>
            </div>

            <div class="save-state" id="saveState" data-state="ready">
                Siap
            </div>

            <button class="save-button" id="saveButton" type="button" data-tooltip="Simpan sekarang (Ctrl+S)" data-tooltip-side="bottom">
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
            </div>
        </footer>
    </main>
</div>

<div class="folder-menu" id="folderMenu" hidden>
    <button type="button" id="renameFolderAction">Ganti nama</button>
    <button type="button" id="deleteFolderAction" class="danger">Hapus folder</button>
</div>

<dialog class="appearance-dialog" id="appearanceDialog" aria-labelledby="appearanceHeading" aria-describedby="appearanceIntro">
    <div class="appearance-heading">
        <h2 id="appearanceHeading">Ruang menulis</h2>
        <button class="writing-button" id="closeAppearance" type="button" autofocus>Tutup</button>
    </div>
    <p class="appearance-intro" id="appearanceIntro">Atur ruang yang nyaman untuk tulisanmu. Perubahan langsung terlihat.</p>
    <div class="appearance-fields">
        <label class="appearance-field" for="appearance-theme">Tema
            <select id="appearance-theme"><option value="light">Terang</option><option value="sepia">Sepia</option><option value="dark">Gelap</option></select>
        </label>
        <label class="appearance-field" for="appearance-width">Lebar tulisan
            <select id="appearance-width"><option value="wide">Lebar penuh — mulai dari kiri</option><option value="writing">Mode Menulis — terpusat</option></select>
        </label>
        <label class="appearance-field" for="appearance-font">Jenis huruf
            <select id="appearance-font"><option value="sans">Sans-serif — Segoe UI</option><option value="serif">Serif — Georgia</option></select>
        </label>
        <label class="appearance-field" for="appearance-size">Ukuran teks
            <select id="appearance-size"><option value="16">16 px</option><option value="18">18 px</option><option value="20">20 px</option><option value="22">22 px</option></select>
        </label>
        <label class="appearance-field" for="appearance-spacing">Jarak baris
            <select id="appearance-spacing"><option value="1.5">Rapat — 1,5</option><option value="1.7">Nyaman — 1,7</option><option value="2">Lega — 2</option></select>
        </label>
    </div>
    <p class="appearance-feedback" id="appearanceFeedback" role="status">Pilihan berlaku untuk tampilan di browser ini. Format khusus di dalam catatan tetap mengikuti tulisanmu.</p>
    <button class="writing-button" id="resetAppearance" type="button">Kembalikan tampilan awal</button>
</dialog>
<div class="toast" id="toast" role="status" aria-live="polite"></div>

<script>
window.BrowserNoteConfig = {
    baseUrl: <?= json_encode(rtrim(base_url(), '/'), JSON_UNESCAPED_SLASHES) ?>,
    tinyMceBase: <?= json_encode(rtrim(base_url('assets/vendor/tinymce'), '/'), JSON_UNESCAPED_SLASHES) ?>
};
</script>

<script src="<?= base_url('assets/vendor/tinymce/tinymce.min.js') ?>"></script>
<script src="<?= base_url('assets/js/writing-preferences.js?v=2') ?>"></script>
<script src="<?= base_url('assets/js/tooltips.js?v=1') ?>"></script>
<script src="<?= base_url('assets/js/browsernote.js?v=writing2') ?>"></script>
<script src="<?= base_url('assets/js/search.js') ?>"></script>
<script src="<?= base_url('assets/js/shortcuts.js') ?>"></script>
<script src="<?= base_url('assets/js/export.js') ?>"></script>
<script src="<?= base_url('assets/js/polish.js?v=writing1') ?>"></script>
<script src="<?= base_url('assets/js/editor-polish-fix.js?v=writing1') ?>"></script>
</body>
</html>