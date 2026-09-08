(() => {
    'use strict';

    const editorCss = `
        html {
            background: inherit;
        }

        body.mce-content-body {
            padding: 22px 28px 72px !important;
            font-family: "Segoe UI", Arial, sans-serif !important;
            font-size: 15px !important;
            font-weight: 400 !important;
            line-height: 1.68 !important;
            letter-spacing: 0 !important;
        }

        body.mce-content-body p,
        body.mce-content-body li,
        body.mce-content-body td,
        body.mce-content-body th {
            font-weight: 400;
        }

        body.mce-content-body p {
            margin-top: 0;
            margin-bottom: 0.72em;
        }

        body.mce-content-body h1 {
            margin-top: 1.2em;
            margin-bottom: 0.48em;
            font-size: 23px !important;
            font-weight: 650 !important;
            line-height: 1.28 !important;
        }

        body.mce-content-body h2 {
            margin-top: 1.15em;
            margin-bottom: 0.46em;
            font-size: 20px !important;
            font-weight: 650 !important;
            line-height: 1.3 !important;
        }

        body.mce-content-body h3 {
            margin-top: 1.1em;
            margin-bottom: 0.42em;
            font-size: 17.5px !important;
            font-weight: 650 !important;
            line-height: 1.32 !important;
        }

        body.mce-content-body h4 {
            margin-top: 1em;
            margin-bottom: 0.4em;
            font-size: 15.5px !important;
            font-weight: 650 !important;
            line-height: 1.35 !important;
        }

        body.mce-content-body h1:first-child,
        body.mce-content-body h2:first-child,
        body.mce-content-body h3:first-child,
        body.mce-content-body h4:first-child {
            margin-top: 0;
        }

        body.mce-content-body strong,
        body.mce-content-body b {
            font-weight: 650;
        }

        body.mce-content-body blockquote {
            margin: 0.9em 0;
            padding-top: 0.15em;
            padding-bottom: 0.15em;
        }

        body.mce-content-body ul,
        body.mce-content-body ol {
            margin-top: 0.45em;
            margin-bottom: 0.75em;
            padding-left: 1.65em;
        }

        body.mce-content-body li {
            margin-bottom: 0.24em;
        }

        body.mce-content-body table {
            margin: 0.9em 0;
            font-size: 14px;
        }

        body.mce-content-body th,
        body.mce-content-body td {
            padding: 6px 8px;
        }

        body.mce-content-body pre {
            margin: 0.85em 0;
            padding: 12px 14px;
            font-family: Consolas, "Cascadia Code", "Courier New", monospace;
            font-size: 13.5px !important;
            line-height: 1.55;
        }

        body.mce-content-body code:not(pre code) {
            font-family: Consolas, "Cascadia Code", "Courier New", monospace;
            font-size: 0.92em;
        }
    `;

    function ensureNormalBlankEditor(editor) {
        const text = (
            editor.getContent({ format: 'text' }) || ''
        ).trim();

        if (text !== '') {
            return;
        }

        try {
            editor.execCommand(
                'FormatBlock',
                false,
                'p'
            );

            editor.formatter.remove('bold');
            editor.formatter.remove('italic');
            editor.formatter.remove('underline');
            editor.formatter.remove('strikethrough');
        } catch (error) {
            console.debug(
                'Normal blank editor setup skipped',
                error
            );
        }
    }

    function injectEditorCss(editor) {
        const doc = editor.getDoc();

        if (!doc || !doc.head) {
            return;
        }

        let style = doc.getElementById(
            'browsernote-stage12-editor-style'
        );

        if (!style) {
            style = doc.createElement('style');
            style.id =
                'browsernote-stage12-editor-style';
            doc.head.appendChild(style);
        }

        style.textContent = editorCss;
    }

    function attach(editor) {
        if (!editor || editor.__browserNotePolishBound) {
            return;
        }

        editor.__browserNotePolishBound = true;

        injectEditorCss(editor);
        ensureNormalBlankEditor(editor);

        editor.on('SetContent', () => {
            injectEditorCss(editor);

            window.setTimeout(() => {
                ensureNormalBlankEditor(editor);
            }, 0);
        });

        editor.on('init', () => {
            injectEditorCss(editor);
            ensureNormalBlankEditor(editor);
        });
    }

    function waitForEditor() {
        let attempts = 0;

        const timer = window.setInterval(() => {
            attempts += 1;

            const editor =
                window.tinymce?.get('noteEditor');

            if (editor?.initialized) {
                attach(editor);
                window.clearInterval(timer);
                return;
            }

            if (attempts >= 60) {
                window.clearInterval(timer);
            }
        }, 150);
    }

    waitForEditor();

    window.BrowserNotePolish = {
        refresh() {
            const editor =
                window.tinymce?.get('noteEditor');

            if (editor?.initialized) {
                injectEditorCss(editor);
                ensureNormalBlankEditor(editor);
            }
        },
    };
})();