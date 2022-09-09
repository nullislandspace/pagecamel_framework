import {CXTextBox} from './cxtextbox.js';
export class CXButton extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.allow_hover = false; // if true, the button will change colors when the mouse is over it  
    }
    _draw() {
        super._draw();
    }
    _mouseInHandler = () => {
        var changed = false;
        if (this.allow_hover) {
            if (this.hover_border_color != undefined && this._border_color != this.hover_border_color) {
                this._default_border_color = this._border_color;
                this._border_color = this.hover_border_color;
                changed = true;
            }
            if (this.hover_text_color != undefined && this._text_color != this.hover_text_color) {
                this._default_text_color = this._text_color;
                this._text_color = this.hover_text_color;
                changed = true;
            }
            if (this.hover_background_color != undefined && this._background_color != this.hover_background_color) {
                this._default_background_color = this._background_color;
                this._background_color = this.hover_background_color;
                changed = true;
            }
        }
        return changed;
    }
    _mouseOutHandler = () => {
        var changed = false;
        if (this.allow_hover) {
            if (this._default_border_color != undefined && this._border_color == this.hover_border_color) {
                this._border_color = this._default_border_color;
                changed = true;
            }
            if (this._default_text_color != undefined && this._text_color == this.hover_text_color) {
                this._text_color = this._default_text_color;
                changed = true;
            }
            if (this._default_background_color != undefined && this._background_color == this.hover_background_color) {
                this._background_color = this._default_background_color;
                changed = true;
            }
        }
        return changed;
    }
    _mouseDownHandler = () => {
        if (this._gradient.length > 0) {
            this._gradient[0] = this._gradient[this._gradient.length - 1];
            return true;
        }
        return false;
    }
    _mouseUpHandler = () => {
        if (this._gradient.length > 0) {
            this._gradient[0] = this._first_gradient_color; // restore the first gradient
            return true;
        }
        return false;
    }
    onClick = () => {
    }
    handleEvent(event) {
        var [x, y] = this._eventToXY(event);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                this.is_mouse_down = true;
                if (this._mouseDownHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
                break;
            case "mouseup":
                if (this.is_mouse_down && this._isInside(x, y)) {
                    this.onClick();
                    console.log("clicked");
                }
                this.is_mouse_down = false;
                if (this._mouseUpHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
            case "mousemove":
                if (this.allow_hover) {
                    if (this._isInside(x, y)) {
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
    }
    /**
     * @param {color} color
     */
    set border_color(color) {
        this._border_color = color;
        this._default_border_color = color;
    }
    /**
     * @returns {color}
     */
    get border_color() {
        return this._border_color;
    }
    /**
     * @param {color} color
     */
    set background_color(color) {
        this._background_color = color;
        this._default_background_color = color;
    }
    get background_color() {
        return this._background_color;
    }
    set hover_border_color(color) {
        this._hover_border_color = color;
    }
    get hover_border_color() {
        return this._hover_border_color;
    }
    set hover_background_color(color) {
        this._hover_background_color = color;
    }
    get hover_background_color() {
        return this._hover_background_color;
    }
    set hover_text_color(color) {
        this._hover_text_color = color;
    }
    get hover_text_color() {
        return this._hover_text_color;
    }
}