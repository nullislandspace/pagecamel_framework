class CXTextInput extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
        this._cursor_pos = 0;
        this._show_cursor = true;
        this._cursor_blink_interval = 500;
        this._cursor_blink_timer = null;
        this._cursor_blink_timer = setInterval(() => {
            this._show_cursor = !this._show_cursor;
            this._drawTextInput();
        }
        , this._cursor_blink_interval);
    }
    _drawTextInput() {
        //draw the text input
        super._draw();
        //draw the cursor
        if (this._show_cursor) {
            this._ctx.fillStyle = this._color;
            this._ctx.fillRect(this._x + this._cursor_pos, this._y, 2, this._height);
        }
    }
    _draw() {
        this._drawTextInput();
    }
}