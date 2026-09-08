(() => {
    'use strict';

    const storageKey = 'browsernote.appearance.v1';
    const defaults = { theme: 'light', width: 'wide', font: 'sans', size: '18', spacing: '1.7' };
    const allowed = {
        theme: ['light', 'sepia', 'dark'], width: ['writing', 'wide'],
        font: ['sans', 'serif'], size: ['16', '18', '20', '22'], spacing: ['1.5', '1.7', '2'],
    };
    let preferences = { ...defaults };
    try {
        const saved = JSON.parse(localStorage.getItem(storageKey));
        for (const key of Object.keys(defaults)) {
            if (allowed[key].includes(saved?.[key])) preferences[key] = saved[key];
        }
        // Move the previous centered default to the left once; retain other preferences.
        if (saved?.layoutVersion !== 2) {
            preferences.width = 'wide';
            localStorage.setItem(storageKey, JSON.stringify({ ...preferences, layoutVersion: 2 }));
        }
    } catch { /* Use defaults if storage is unavailable or invalid. */ }

    const shell = document.getElementById('appShell');
    const dialog = document.getElementById('appearanceDialog');
    const focusButton = document.getElementById('focusModeButton');
    const appearanceButton = document.getElementById('appearanceButton');
    const feedback = document.getElementById('appearanceFeedback');
    let editor = null;
    let focused = false;

    function apply() {
        document.documentElement.dataset.theme = preferences.theme;
        document.documentElement.style.colorScheme = preferences.theme === 'dark' ? 'dark' : 'light';
        document.querySelector('meta[name="color-scheme"]').content = preferences.theme === 'dark' ? 'dark' : 'light';
        shell.dataset.width = preferences.width;
        for (const key of Object.keys(defaults)) {
            document.getElementById(`appearance-${key}`).value = preferences[key];
        }
        if (!editor?.getDoc()?.head) return;
        const doc = editor.getDoc();
        if (!doc.getElementById('writing-content-style')) {
            const link = doc.createElement('link');
            link.id = 'writing-content-style';
            link.rel = 'stylesheet';
            link.href = `${window.BrowserNoteConfig.baseUrl}/assets/css/writing-content.css?v=2`;
            doc.head.appendChild(link);
        }
        // Preferences belong to the editor document, never to saved note HTML.
        doc.documentElement.dataset.writingTheme = preferences.theme;
        doc.documentElement.dataset.writingWidth = preferences.width;
        doc.documentElement.style.setProperty('--writing-font', preferences.font === 'serif'
            ? 'Georgia, "Times New Roman", serif' : '"Segoe UI", Arial, sans-serif');
        doc.documentElement.style.setProperty('--writing-size', `${preferences.size}px`);
        doc.documentElement.style.setProperty('--writing-spacing', preferences.spacing);
    }

    function persist() {
        try {
            localStorage.setItem(storageKey, JSON.stringify({ ...preferences, layoutVersion: 2 }));
            feedback.textContent = 'Pilihan tersimpan di browser ini.';
        } catch {
            feedback.textContent = 'Pilihan diterapkan untuk sesi ini. Penyimpanan browser tidak tersedia.';
        }
        apply();
    }

    function setFocus(value) {
        if (value && editor?.plugins.fullscreen?.isFullscreen()) {
            editor.execCommand('mceFullScreen');
        }
        focused = value;
        shell.classList.toggle('writing-focus', focused);
        focusButton.setAttribute('aria-pressed', String(focused));
        focusButton.textContent = focused ? 'Keluar Fokus' : 'Fokus';
        focusButton.title = focused ? 'Keluar mode fokus (Esc)' : 'Mode fokus';
        // Preserve the user's existing collapsed/open sidebar preference.
        editor?.focus();
    }

    function handleEscape(event) {
        if (event.key !== 'Escape' || event.defaultPrevented || !focused || dialog.open) return;
        if (document.querySelector('.tox-dialog, .tox-menu, .quick-note-overlay:not([hidden]), .shortcut-overlay:not([hidden]), .export-overlay:not([hidden])')) return;
        event.preventDefault();
        setFocus(false);
    }

    appearanceButton.addEventListener('click', () => dialog.showModal());
    document.getElementById('closeAppearance').addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', () => appearanceButton.focus());
    dialog.addEventListener('click', (event) => {
        if (event.target !== dialog) return;
        const rect = dialog.getBoundingClientRect();
        if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
    });
    for (const key of Object.keys(defaults)) {
        document.getElementById(`appearance-${key}`).addEventListener('change', (event) => {
            if (!allowed[key].includes(event.target.value)) return;
            preferences[key] = event.target.value;
            persist();
        });
    }
    document.getElementById('resetAppearance').addEventListener('click', () => {
        preferences = { ...defaults };
        persist();
    });
    focusButton.addEventListener('click', () => setFocus(!focused));
    document.addEventListener('keydown', handleEscape);
    window.addEventListener('storage', (event) => {
        if (event.key !== storageKey) return;
        try {
            const next = JSON.parse(event.newValue);
            preferences = { ...defaults };
            for (const key of Object.keys(defaults)) {
                if (allowed[key].includes(next?.[key])) preferences[key] = next[key];
            }
            apply();
        } catch { /* Ignore malformed settings from another tab. */ }
    });
    window.BrowserNoteAppearance = {
        attach(instance) {
            editor = instance;
            editor.on('keydown', handleEscape);
            editor.on('SetContent', apply);
            apply();
        },
    };
    if (window.matchMedia('(max-width: 760px)').matches) shell.classList.add('sidebar-collapsed');
    apply();
})();
