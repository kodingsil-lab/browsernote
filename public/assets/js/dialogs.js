(() => {
    'use strict';

    const queue = [];
    let active = null;
    let elements = null;

    function build() {
        if (elements) {
            return elements;
        }

        const dialog = document.createElement('dialog');
        dialog.className = 'app-dialog';
        dialog.setAttribute('aria-labelledby', 'appDialogTitle');
        dialog.setAttribute('aria-describedby', 'appDialogMessage');

        const form = document.createElement('form');
        form.className = 'app-dialog__form';
        form.method = 'dialog';

        const body = document.createElement('div');
        body.className = 'app-dialog__body';

        const icon = document.createElement('div');
        icon.className = 'app-dialog__icon';
        icon.setAttribute('aria-hidden', 'true');

        const content = document.createElement('div');
        content.className = 'app-dialog__content';

        const title = document.createElement('h2');
        title.className = 'app-dialog__title';
        title.id = 'appDialogTitle';

        const message = document.createElement('p');
        message.className = 'app-dialog__message';
        message.id = 'appDialogMessage';

        const field = document.createElement('label');
        field.className = 'app-dialog__field';
        field.hidden = true;

        const fieldLabel = document.createElement('span');
        const input = document.createElement('input');
        input.className = 'app-dialog__input';
        input.type = 'text';
        input.autocomplete = 'off';

        field.append(fieldLabel, input);
        content.append(title, message, field);
        body.append(icon, content);

        const actions = document.createElement('div');
        actions.className = 'app-dialog__actions';

        const cancelButton = document.createElement('button');
        cancelButton.className = 'app-dialog__button';
        cancelButton.type = 'submit';
        cancelButton.value = 'cancel';
        cancelButton.formNoValidate = true;

        const confirmButton = document.createElement('button');
        confirmButton.className = 'app-dialog__button app-dialog__button--primary';
        confirmButton.type = 'submit';
        confirmButton.value = 'confirm';

        actions.append(cancelButton, confirmButton);
        form.append(body, actions);
        dialog.appendChild(form);
        document.body.appendChild(dialog);

        form.addEventListener('submit', (event) => {
            if (
                active?.options.kind === 'prompt'
                && active.options.required !== false
                && input.value.trim() === ''
            ) {
                event.preventDefault();
                input.setCustomValidity('Bagian ini perlu diisi.');
                input.reportValidity();
                return;
            }

            input.setCustomValidity('');
        });

        input.addEventListener('input', () => {
            input.setCustomValidity('');
        });

        dialog.addEventListener('keydown', (event) => {
            event.stopPropagation();
        });

        dialog.addEventListener('cancel', (event) => {
            event.preventDefault();
            dialog.close('cancel');
        });

        dialog.addEventListener('click', (event) => {
            if (event.target === dialog) {
                dialog.close('cancel');
            }
        });

        dialog.addEventListener('close', finish);

        elements = {
            dialog,
            icon,
            title,
            message,
            field,
            fieldLabel,
            input,
            cancelButton,
            confirmButton,
        };

        return elements;
    }

    function finish() {
        if (!active) {
            return;
        }

        const { options, resolve } = active;
        const action = elements.dialog.returnValue;
        let result = action === 'confirm';

        if (options.kind === 'prompt') {
            result = action === 'confirm'
                ? elements.input.value
                : null;
        } else if (options.kind === 'alert') {
            result = true;
        }

        active = null;
        resolve(result);
        window.setTimeout(openNext, 0);
    }

    function openNext() {
        if (active || queue.length === 0) {
            return;
        }

        active = queue.shift();
        const options = active.options;
        const ui = build();
        const danger = options.variant === 'danger';

        ui.dialog.returnValue = '';
        ui.dialog.dataset.variant = danger ? 'danger' : 'default';
        ui.icon.textContent = danger
            ? '!'
            : options.kind === 'prompt'
                ? '+'
                : options.kind === 'confirm'
                    ? '?'
                    : 'i';
        ui.title.textContent = options.title || (
            options.kind === 'prompt'
                ? 'Masukkan informasi'
                : options.kind === 'confirm'
                    ? 'Konfirmasi'
                    : 'Pemberitahuan'
        );
        ui.message.textContent = options.message || '';
        ui.message.hidden = !options.message;

        const isPrompt = options.kind === 'prompt';
        ui.field.hidden = !isPrompt;
        ui.fieldLabel.textContent = options.inputLabel || 'Nama';
        ui.input.value = isPrompt ? String(options.initialValue || '') : '';
        ui.input.placeholder = options.placeholder || '';
        ui.input.maxLength = Number(options.maxLength) > 0
            ? Number(options.maxLength)
            : 255;
        ui.input.required = isPrompt && options.required !== false;
        ui.input.setCustomValidity('');

        const isAlert = options.kind === 'alert';
        ui.cancelButton.hidden = isAlert;
        ui.cancelButton.textContent = options.cancelText || 'Batal';
        ui.confirmButton.textContent = options.confirmText || (
            isAlert ? 'Mengerti' : 'Lanjutkan'
        );
        ui.confirmButton.className = danger
            ? 'app-dialog__button app-dialog__button--danger'
            : 'app-dialog__button app-dialog__button--primary';

        ui.dialog.showModal();

        window.setTimeout(() => {
            if (isPrompt) {
                ui.input.focus();
                ui.input.select();
            } else if (danger && !isAlert) {
                ui.cancelButton.focus();
            } else {
                ui.confirmButton.focus();
            }
        }, 0);
    }

    function enqueue(options) {
        return new Promise((resolve) => {
            queue.push({ options, resolve });
            openNext();
        });
    }

    window.BrowserNoteDialog = {
        alert(options = {}) {
            return enqueue({ ...options, kind: 'alert' });
        },
        confirm(options = {}) {
            return enqueue({ ...options, kind: 'confirm' });
        },
        prompt(options = {}) {
            return enqueue({ ...options, kind: 'prompt' });
        },
    };
})();
