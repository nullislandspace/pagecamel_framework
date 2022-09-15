import { CXTextBox } from "./cxtextbox.js";
export declare class CXTextInput extends CXTextBox {
    /** @protected */
    protected _cursorPos: number;
    /** @protected */
    protected _cursor_color: string;
    /** @protected */
    protected _cursor_width: number;
    /** @protected */
    protected _cursor_active: boolean;
    /** @protected */
    protected _cursor_blink_interval: number;
    /** @protected */
    protected _cursor_visible_blink: boolean;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative: any, redraw: any);
    /**
     * @param {number} x the x coordinate of the mouse
     * @description converts the mouse coordinates to the cursor position in the text
     */
    _showCursor(x: number): void;
    /**
     * @param {boolean} ctrl - if the control key is pressed
     * @protected
     */
    protected _moveCursorLeft(ctrl: boolean): void;
    /**
     * @param {boolean} ctrl - if the control key is pressed
     * @protected
     */
    protected _moveCursorRight(ctrl: boolean): void;
    /**
     * @protected
     * @description overwritten the checkMouseDown function to handle event when clicked outside the text input, so the cursor gets disabled
     */
    protected _checkMouseDown(x: number, y: number): boolean;
    /**
     * @param {event} event - the event object
     * @protected
     * @description changes the text when a key is pressed
     */
    protected _changeText(event: KeyboardEvent): void;
    /**
     * @protected
     * @description return true if the text should be changed by the event | false if not
     * @param {event} event - the event object
     * @returns {boolean}
     */
    protected _onKeyDown(event: KeyboardEvent): boolean;
    /**
     * @description handles the event
     * @params {event} event - the event
     * @protected
     */
    protected _handleEvent(event: Event): boolean;
    /**
     * @protected
     */
    protected _drawCursor(): void;
    /**
     * @protected
     */
    _draw(): void;
}
