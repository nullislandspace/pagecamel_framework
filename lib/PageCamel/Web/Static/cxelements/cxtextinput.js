//rewrite UITextInput to CXTextInput
class CXTextInput extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super._text_alignment = 'left';
        super.takes_keyboard_input = true;
        this.type = 'text'; //text, number, float, euro

        this._cursor_visible = false;
        this._cursor_position = 0;
        this._cursor_blink_timer = 0;
        this._cursor_blink_interval = 500;
        this._cursor_blink_visible = true;
        this._cursor_color = 'black';
        this._cursor_width = 1; // 1 pixel
        this._cursor_height = 0.8; // 80% of the height
        this._cursor_y = this.ypixel + this.border_width;
        this._cursor_x = this.xpixel + this.border_width;
    }
    _showCursor(x) {
        this._cursor_visible = true;
        this._ctx.font = this._font_size + 'px ' + this._font_family;
        var text_x = this._xpixel + this.border_width;
        var cursor_text_position = 0;
        // calculate the cursor position and give back the index of the character
        for (var i = 0; i < this._text.length; i++) {
            var text_metrics = this._ctx.measureText(this._text.substring(0, i));
            if (text_metrics.width > x - text_x) {
                cursor_text_position = i;
                break;
            }
        }
        var text_metrics = this._ctx.measureText(this._text.substring(0, cursor_text_position));
        this._cursor_position = cursor_text_position; // set the cursor position to the calculated index
        this._cursor_x = text_x + text_metrics.width; // get the x position of the cursor
        this._cursor_visible = true; // hide the cursor
        console.log('show cursor at ' + this._cursor_x);

    }
    handleEvent(event) {
        super.handleEvent(event);
        var [x, y] = this._eventToXY(event);
        if (event.type == 'keydown') {
            console.log(event.key);
            //this.onKeyDown(e);
        } else if (event.type == 'keyup') {
            //this.onKeyUp(e);
        } else if (event.type == 'mousedown') {
            if (this._isInside(x, y)) {
                this._showCursor(x);
            }
        }
    }
    _drawCursor() {
        this._ctx.fillStyle = this._cursor_color;
        this._ctx.fillRect(this._cursor_x, this._cursor_y, this._cursor_width, this._cursor_height);
    }
    _draw() {
        super._draw();
        if (this._cursor_visible) {
            this._drawCursor();
        }
    }

}
