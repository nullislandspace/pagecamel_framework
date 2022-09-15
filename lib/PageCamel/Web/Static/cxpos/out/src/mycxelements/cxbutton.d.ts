import { CXTextBox } from './cxtextbox.js';
export declare class CXButton extends CXTextBox {
    /**@protected */
    protected allow_hover: boolean;
    /**@protected */
    protected _default_border_color: string;
    /**@protected */
    protected _default_text_color: string;
    /**@protected */
    protected _default_background_color: string;
    /**@protected */
    protected _is_mouse_down: boolean;
    /**@protected */
    protected _hover_border_color: string;
    /**@protected */
    protected _hover_text_color: string;
    /**@protected */
    protected _hover_background_color: string;
    /**
     * @constructor
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean, redraw: boolean);
    /**
     * @description Draws the button
     * @protected
     */
    _draw(): void;
    /**
     * @description Gets called when mouse enters the button
     * @protected
     * @returns {boolean}
     */
    protected _mouseInHandler: () => boolean;
    /**
     * @description Gets called when the mouse leaves the button
     * @returns {boolean}
     * @protected
     */
    protected _mouseOutHandler: () => boolean;
    /**
     * @description gets called when the mouse is down on the button
     * @protected
     * @returns {boolean}
     */
    protected _mouseDownHandler: () => boolean;
    /**
     * @description gets called when the mouse is up
     * @protected
     * @returns {boolean}
     */
    protected _mouseUpHandler: () => boolean;
    /**
     * @description override this to execute code when the button is clicked
     */
    onClick: () => void;
    _handleEvent(event: Event): boolean;
    /**
     * @param {string} color
     */
    set border_color(color: string);
    /**
     * @returns {color}
     */
    get border_color(): string;
    /**
     * @param {string} color
     */
    set background_color(color: string);
    get background_color(): string;
    set hover_border_color(color: string);
    get hover_border_color(): string;
    set hover_background_color(color: string);
    get hover_background_color(): string;
    set hover_text_color(color: string);
    get hover_text_color(): string;
}
