import { CXTextBox } from './cxtextbox.js';
export class CXButton extends CXTextBox {
    /**@protected */
    protected _allow_hover: boolean;
    /**@protected */
    protected _default_border_color: string;
    /**@protected */
    protected _default_text_color: string;
    /**@protected */
    protected _default_background_color: string;
    /**@protected */
    protected _is_mouse_down: boolean;
    /**@protected */
    protected _hover_border_color?: string | undefined;
    /**@protected */
    protected _hover_text_color?: string | undefined;
    /**@protected */
    protected _hover_background_color?: string | undefined;

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
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);

        this._allow_hover = false; // if true, the button will change colors when the mouse is over it
        this._is_mouse_down = false;
        this._default_border_color = this._border_color;
        this._default_text_color = this._text_color;
        this._default_background_color = this._background_color;

        this._hover_border_color = this._border_color;
        this._hover_text_color = this._text_color;
        this._hover_background_color = this._background_color;

    }
    /**
     * @description Draws the button
     * @protected
     */
    protected _draw(): void {
        super._draw();
    }
    /**
     * @description Gets called when mouse enters the button
     * @protected 
     * @returns {boolean}
     */
    protected _mouseInHandler: () => boolean = (): boolean => {
        console.log("Hover Mouse In", this._name);
        var changed = false;
        if (this._allow_hover) {
            if (this._hover_border_color != undefined && this._border_color != this._hover_border_color) {
                this._default_border_color = this._border_color;
                this._border_color = this._hover_border_color;
                changed = true;
            }
            if (this._hover_text_color != undefined && this._text_color != this._hover_text_color) {
                this._default_text_color = this._text_color;
                this._text_color = this._hover_text_color;
                changed = true;
            }
            if (this._hover_background_color != undefined && this._background_color != this._hover_background_color) {
                this._default_background_color = this._background_color;
                this._background_color = this._hover_background_color;
                changed = true;
            }
        }
        return changed;
    }
    /**
     * @description Gets called when the mouse leaves the button
     * @returns {boolean}
     * @protected
     */
    protected _mouseOutHandler: () => boolean = (): boolean => {
        var changed = false;
        if (this._allow_hover) {
            if (this._default_border_color != undefined && this._border_color == this._hover_border_color) {
                this._border_color = this._default_border_color;
                changed = true;
            }
            if (this._default_text_color != undefined && this._text_color == this._hover_text_color) {
                this._text_color = this._default_text_color;
                changed = true;
            }
            if (this._default_background_color != undefined && this._background_color == this._hover_background_color) {
                this._background_color = this._default_background_color;
                changed = true;
            }
        }
        return changed;
    }
    /**
     * @description gets called when the mouse is down on the button
     * @protected
     * @returns {boolean}
     */
    protected _mouseDownHandler: () => boolean = (): boolean => {
        if (this._gradient.length > 0) {
            this._gradient[0] = this._gradient[this._gradient.length - 1];
            return true;
        }
        return false;
    }
    /**
     * @description gets called when the mouse is up
     * @protected
     * @returns {boolean}
     */
    protected _mouseUpHandler: () => boolean = (): boolean => {
        if (this._gradient.length > 0) {
            this._gradient[0] = this._first_gradient_color; // restore the first gradient
            return true;
        }
        return false;
    }

    /**
     * @description override this to execute code when the button is clicked
     */
    onClick: (object: this) => void = (): void => {
    }

    protected _handleEvent(event: Event): boolean {

        var redraw = false;
        switch (event.type) {
            case "mousedown":
                var [x, y] = this._eventToXY(event as MouseEvent);
                this._is_mouse_down = true;
                if (this._mouseDownHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
                break;
            case "mouseup":
                var [x, y] = this._eventToXY(event as MouseEvent);
                if (this._is_mouse_down && this.isInside(x, y)) {
                    this.onClick(this);
                    console.log("clicked");
                }
                this._is_mouse_down = false;
                if (this._mouseUpHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
            case "mousemove":
                var [x, y] = this._eventToXY(event as MouseEvent);
                if (this._allow_hover) {
                    if (this.isInside(x, y)) {
                        if (this._mouseInHandler()) {
                            this._has_changed = true;
                            redraw = true;
                        }
                    }
                    else {
                        if (this._mouseOutHandler()) {
                            this._has_changed = true;
                            redraw = true;
                        }
                    }
                }
                break;
            case "mouseleave":
                if (this._mouseUpHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
                break;
        }
        if (redraw && this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
        return this._has_changed;
    }
    /**
     * @param {string} color
     */
    set border_color(color: string) {
        this._border_color = color;
        this._default_border_color = color;
    }
    /**
     * @returns {string}
     */
    get border_color(): string {
        return this._border_color;
    }
    /**
     * @param {string} color
     */
    set background_color(color: string) {
        this._background_color = color;
        this._default_background_color = color;
    }
    get background_color(): string {
        return this._background_color;
    }
    /**
     * if allow_hover is true, the button will change border color when the mouse is over it
     * @param color
     */
    set hover_border_color(color: string | undefined) {
        this._hover_border_color = color;
    }
    get hover_border_color(): string | undefined {
        return this._hover_border_color;
    }
    /**
     * if allow_hover is true, the button will change the background color when the mouse is over it
     * @param color
     */
    set hover_background_color(color: string | undefined) {
        this._hover_background_color = color;
    }
    get hover_background_color(): string | undefined {
        return this._hover_background_color;
    }
    /**
     * if allow_hover is true, the button will change text color when the mouse is over it
     * @param color
     */
    set hover_text_color(color: string | undefined) {
        this._hover_text_color = color;
    }
    get hover_text_color(): string | undefined {
        return this._hover_text_color;
    }
    /**
     * if true, the button will change color when the mouse is over it
     * @param allow
     */
    set allow_hover(allow: boolean) {
        this._allow_hover = allow;
    }
    get allow_hover(): boolean {
        return this._allow_hover;
    }

}