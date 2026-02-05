/**
 * Copyright (c) 2017 The xterm.js authors. All rights reserved.
 * @license MIT
 *
 * FitAddon - Automatically resize terminal to fit its container
 * Based on @xterm/addon-fit
 */

(function(global) {
    'use strict';

    const MINIMUM_COLS = 2;
    const MINIMUM_ROWS = 1;
    const DEFAULT_SCROLL_BAR_WIDTH = 14;

    class FitAddon {
        constructor() {
            this._terminal = undefined;
        }

        activate(terminal) {
            this._terminal = terminal;
        }

        dispose() {
            this._terminal = undefined;
        }

        fit() {
            const dims = this.proposeDimensions();
            if (!dims || !this._terminal || isNaN(dims.cols) || isNaN(dims.rows)) {
                return;
            }

            const core = this._terminal._core;

            // Force a full render if dimensions changed
            if (this._terminal.rows !== dims.rows || this._terminal.cols !== dims.cols) {
                core._renderService.clear();
                this._terminal.resize(dims.cols, dims.rows);
            }
        }

        proposeDimensions() {
            if (!this._terminal) {
                return undefined;
            }

            if (!this._terminal.element || !this._terminal.element.parentElement) {
                return undefined;
            }

            const core = this._terminal._core;
            const dims = core._renderService.dimensions;

            if (dims.css.cell.width === 0 || dims.css.cell.height === 0) {
                return undefined;
            }

            const scrollbarWidth = (this._terminal.options.scrollback === 0)
                ? 0
                : (this._terminal.options.overviewRuler?.width || DEFAULT_SCROLL_BAR_WIDTH);

            const parentElementStyle = window.getComputedStyle(this._terminal.element.parentElement);
            const parentElementHeight = parseInt(parentElementStyle.getPropertyValue('height'));
            const parentElementWidth = Math.max(0, parseInt(parentElementStyle.getPropertyValue('width')));

            const elementStyle = window.getComputedStyle(this._terminal.element);
            const elementPadding = {
                top: parseInt(elementStyle.getPropertyValue('padding-top')),
                bottom: parseInt(elementStyle.getPropertyValue('padding-bottom')),
                right: parseInt(elementStyle.getPropertyValue('padding-right')),
                left: parseInt(elementStyle.getPropertyValue('padding-left'))
            };

            const elementPaddingVer = elementPadding.top + elementPadding.bottom;
            const elementPaddingHor = elementPadding.right + elementPadding.left;
            const availableHeight = parentElementHeight - elementPaddingVer;
            const availableWidth = parentElementWidth - elementPaddingHor - scrollbarWidth;

            return {
                cols: Math.max(MINIMUM_COLS, Math.floor(availableWidth / dims.css.cell.width)),
                rows: Math.max(MINIMUM_ROWS, Math.floor(availableHeight / dims.css.cell.height))
            };
        }
    }

    // Export for different module systems
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { FitAddon: FitAddon };
    } else {
        global.FitAddon = { FitAddon: FitAddon };
    }

})(typeof globalThis !== 'undefined' ? globalThis : (typeof window !== 'undefined' ? window : this));
