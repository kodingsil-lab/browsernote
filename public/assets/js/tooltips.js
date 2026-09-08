(() => {
    'use strict';

    const selector = '[data-tooltip]';
    const viewportMargin = 8;
    const gap = 9;
    let tooltip = null;
    let activeTrigger = null;
    let showTimer = null;
    let previousDescription = null;

    function ensureTooltip() {
        if (tooltip) {
            return tooltip;
        }

        tooltip = document.createElement('div');
        tooltip.id = 'appTooltip';
        tooltip.className = 'app-tooltip';
        tooltip.setAttribute('role', 'tooltip');
        tooltip.hidden = true;
        document.body.appendChild(tooltip);

        return tooltip;
    }

    function clamp(value, minimum, maximum) {
        return Math.min(Math.max(value, minimum), maximum);
    }

    function positionTooltip(trigger) {
        const bubble = ensureTooltip();
        const triggerRect = trigger.getBoundingClientRect();
        const bubbleRect = bubble.getBoundingClientRect();
        const preferred = trigger.dataset.tooltipSide || 'top';
        const spaces = {
            top: triggerRect.top,
            bottom: window.innerHeight - triggerRect.bottom,
            left: triggerRect.left,
            right: window.innerWidth - triggerRect.right,
        };
        const required = {
            top: bubbleRect.height + gap,
            bottom: bubbleRect.height + gap,
            left: bubbleRect.width + gap,
            right: bubbleRect.width + gap,
        };
        const order = [preferred, 'top', 'bottom', 'right', 'left'];
        const side = order.find((candidate, index) =>
            order.indexOf(candidate) === index
            && spaces[candidate] >= required[candidate]
        ) || preferred;

        let left = triggerRect.left + ((triggerRect.width - bubbleRect.width) / 2);
        let top = triggerRect.top - bubbleRect.height - gap;

        if (side === 'bottom') {
            top = triggerRect.bottom + gap;
        } else if (side === 'left') {
            left = triggerRect.left - bubbleRect.width - gap;
            top = triggerRect.top + ((triggerRect.height - bubbleRect.height) / 2);
        } else if (side === 'right') {
            left = triggerRect.right + gap;
            top = triggerRect.top + ((triggerRect.height - bubbleRect.height) / 2);
        }

        bubble.style.left = `${Math.round(clamp(
            left,
            viewportMargin,
            window.innerWidth - bubbleRect.width - viewportMargin
        ))}px`;
        bubble.style.top = `${Math.round(clamp(
            top,
            viewportMargin,
            window.innerHeight - bubbleRect.height - viewportMargin
        ))}px`;
        bubble.dataset.side = side;
    }

    function show(trigger, immediate = false) {
        const text = trigger.dataset.tooltip?.trim();

        if (!text || trigger.disabled) {
            return;
        }

        window.clearTimeout(showTimer);

        if (activeTrigger === trigger) {
            positionTooltip(trigger);
            return;
        }

        hide();
        showTimer = window.setTimeout(() => {
            showTimer = null;
            activeTrigger = trigger;
            const bubble = ensureTooltip();
            bubble.textContent = text;
            bubble.hidden = false;
            previousDescription = trigger.getAttribute('aria-describedby');
            trigger.setAttribute('aria-describedby', bubble.id);
            positionTooltip(trigger);
            bubble.classList.add('is-visible');
        }, immediate ? 0 : 420);
    }

    function hide() {
        window.clearTimeout(showTimer);

        if (!tooltip || !activeTrigger) {
            return;
        }

        tooltip.classList.remove('is-visible');
        tooltip.hidden = true;

        if (previousDescription === null) {
            activeTrigger.removeAttribute('aria-describedby');
        } else {
            activeTrigger.setAttribute('aria-describedby', previousDescription);
        }

        activeTrigger = null;
        previousDescription = null;
    }

    document.addEventListener('pointerover', (event) => {
        const trigger = event.target.closest?.(selector);

        if (trigger && !trigger.contains(event.relatedTarget)) {
            show(trigger);
        }
    });

    document.addEventListener('pointerout', (event) => {
        const trigger = event.target.closest?.(selector);

        if (trigger && !trigger.contains(event.relatedTarget)) {
            hide();
        }
    });

    document.addEventListener('focusin', (event) => {
        const trigger = event.target.closest?.(selector);

        if (trigger) {
            show(trigger, true);
        }
    });

    document.addEventListener('focusout', (event) => {
        if (event.target.closest?.(selector)) {
            hide();
        }
    });

    document.addEventListener('click', hide);
    document.addEventListener('scroll', hide, true);
    window.addEventListener('resize', hide);
})();
