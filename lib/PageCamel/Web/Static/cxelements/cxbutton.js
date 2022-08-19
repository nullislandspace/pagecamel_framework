class CXButton extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);

        this.allow_hover = false; // if true, the button will change colors when the mouse is over it  
    }
    _drawButton() {
        this._drawTextBox();
    }
    _draw() {
        this._drawButton();
    }
    _mouseInHandler = () => {
        var changed = false;
        if (this.allow_hover) {
            if (this.hover_frame_color != undefined && this._frame_color != this.hover_frame_color) {
                this._default_frame_color = this._frame_color;
                this._frame_color = this.hover_frame_color;
                changed = true;
            }
            if (this.hover_text_color != undefined && this._text_color != this.hover_text_color) {
                this._default_text_color = this._text_color;
                this._text_color = this.hover_text_color;
                changed = true;
            }
            if (this.hover_box_color != undefined && this._box_color != this.hover_box_color) {
                this._default_box_color = this._box_color;
                this._box_color = this.hover_box_color;
                changed = true;
            }
        }
        return changed;
    }
    _mouseOutHandler = () => {
        var changed = false;
        if (this.allow_hover) {
            if (this._default_frame_color != undefined && this._frame_color == this.hover_frame_color) {
                this._frame_color = this._default_frame_color;
                changed = true;
            }
            if (this._default_text_color != undefined && this._text_color == this.hover_text_color) {
                this._text_color = this._default_text_color;
                changed = true;
            }
            if (this._default_box_color != undefined && this._box_color == this.hover_box_color) {
                this._box_color = this._default_box_color;
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
    handleEvent(event) {
        var [x, y] = this._eventToXY(event);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                if (this._mouseDownHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
                break;
            case "mouseup":
                if (this._mouseUpHandler()) {
                    this._has_changed = true;
                    redraw = true;
                }
            case "mousemove":
                if (this.allow_hover) {
                    if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
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
    set frame_color(color) {
        this._frame_color = color;
        this._default_frame_color = color;
    }
    get frame_color() {
        return this._frame_color;
    }
    set box_color(color) {
        this._box_color = color;
        this._default_box_color = color;
    }
    get box_color() {
        return this._box_color;
    }
    set hover_frame_color(color) {
        this._hover_frame_color = color;
    }
    get hover_frame_color() {
        return this._hover_frame_color;
    }
    set hover_box_color(color) {
        this._hover_box_color = color;
    }
    get hover_box_color() {
        return this._hover_box_color;
    }
    set hover_text_color(color) {
        this._hover_text_color = color;
    }
    get hover_text_color() {
        return this._hover_text_color;
    }
}