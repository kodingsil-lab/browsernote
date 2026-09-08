(() => {
    'use strict';

    const styleText = `
        body.mce-content-body {
            padding: 22px 30px 72px !important;
            font-family: "Segoe UI", Arial, sans-serif !important;
            font-size: 15px !important;
            font-weight: 400 !important;
            line-height: 1.68 !important;
            letter-spacing: 0 !important;
        }

        body.mce-content-body p {
            margin: 0 0 0.72em;
            font-size: 15px;
            font-weight: 400;
        }

        body.mce-content-body h1 {
            margin: 1.15em 0 0.45em;
            font-size: 23px !important;
            font-weight: 650 !important;
            line-height: 1.28;
        }

        body.mce-content-body h2 {
            margin: 1.1em 0 0.42em;
            font-size: 20px !important;
            font-weight: 650 !important;
            line-height: 1.3;
        }

        body.mce-content-body h3 {
            margin: 1.05em 0 0.4em;
            font-size: 17px !important;
            font-weight: 650 !important;
            line-height: 1.32;
        }

        body.mce-content-body h4 {
            margin: 1em 0 0.38em;
            font-size: 15.5px !important;
            font-weight: 650 !important;
            line-height: 1.35;
        }

        body.mce-content-body strong,
        body.mce-content-body b {
            font-weight: 650;
        }

        body.mce-content-body li {
            margin-bottom: 0.2em;
        }

        body.mce-content-body table {
            font-size: 14px;
        }

        body.mce-content-body th,
        body.mce-content-body td {
            padding: 6px 8px;
        }

        body.mce-content-body pre {
            font-family: Consolas, "Cascadia Code", "Courier New", monospace;
            font-size: 13.5px !important;
            line-height: 1.55;
        }
    `;

    function installStyle(editor) {
        const doc = editor.getDoc();

        if (!doc?.head) {
            return;
        }

        let style = doc.getElementById(
            'browsernote-stage12a-writing-style'
        );

        if (!style) {
            style = doc.createElement('style');
            style.id =
                'browsernote-stage12a-writing-style';

            doc.head.appendChild(style);
        }

        style.textContent = styleText;
    }

    function normalizeEmptyEditor(editor) {
        const text = (
            editor.getContent({ format: 'text' }) || ''
        ).trim();

        if (text !== '') {
            return;
        }

        /*
         * Only normalize truly empty notes.
         * Existing formatting is never rewritten.
         */
        const body = editor.getBody();

        if (!body) {
            return;
        }

        if (
            body.childElementCount === 0
            || (
                body.childElementCount === 1
                && body.firstElementChild?.textContent.trim() === ''
            )
        ) {
            body.innerHTML = '<p><br data-mce-bogus="1"></p>';

            editor.selection.select(
                body.firstElementChild,
                true
            );

            editor.selection.collapse(true);
        }

        try {
            editor.formatter.remove('bold');
            editor.formatter.remove('italic');
            editor.formatter.remove('underline');
            editor.formatter.remove('strikethrough');
        } catch (error) {
            console.debug(
                'Default format cleanup skipped',
                error
            );
        }
    }

    function attach(editor) {
        if (
            !editor
            || editor.__browserNoteStage12AFixed
        ) {
            return;
        }

        editor.__browserNoteStage12AFixed = true;

        installStyle(editor);
        normalizeEmptyEditor(editor);

        editor.on('SetContent', () => {
            installStyle(editor);

            window.setTimeout(() => {
                normalizeEmptyEditor(editor);
            }, 0);
        });

        editor.on('init', () => {
            installStyle(editor);
            normalizeEmptyEditor(editor);
        });
    }

    let attempts = 0;

    const timer = window.setInterval(() => {
        attempts += 1;

        const editor =
            window.tinymce?.get('noteEditor');

        if (editor) {
            attach(editor);
            window.clearInterval(timer);
            return;
        }

        if (attempts >= 80) {
            window.clearInterval(timer);
        }
    }, 125);

    window.BrowserNoteUIFix = {
        refresh() {
            const editor =
                window.tinymce?.get('noteEditor');

            if (editor) {
                installStyle(editor);
                normalizeEmptyEditor(editor);
            }
        },
    };
})();