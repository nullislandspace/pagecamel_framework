import { CXBox } from "./cxbox.js";
export class CXScrollBar extends CXBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._scrollbarPressed = (event) => {
            var [x, y] = this._eventToXY(event);
            this._mouse_down_scrollbar_ypos = y - this.scrollbar.ypixel;
            this._scrollbar_pressed = true;
        };
        this._mouse_down_scrollbar_ypos = 0;
        this.background_color = "white";
        this.scrollbar = new CXBox(ctx, 0.0, 0.0, 1.0, 1.0, true, false);
        this.scrollbar.background_color = "black";
        this.scrollbar.border_width = 0;
        this._rows = 1;
        this._rows_per_page = 1;
        this._scroll_position = 0;
        this.pixels_per_row = this.heightpixel / this._rows;
        this._scrollbar_pressed = false;
    }
    _drawScrollbar() {
        this.scrollbar.height = this._getScrollbarHeight();
        this.scrollbar.ypos = this._getScrollbarYPos();
        super._draw();
        this.scrollbar.draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
    }
    _getScrollbarYPos() {
        this._scroll_position = Math.max(0, Math.min(this._scroll_position, this._rows - this._rows_per_page));
        return 1 / this._rows * this._scroll_position;
    }
    _getScrollbarHeight() {
        this.pixels_per_row = this.heightpixel / this._rows;
        if (this._rows > this._rows_per_page) {
            var height = 1 / (this._rows / this._rows_per_page);
            return height;
        }
        return 1;
    }
    _draw() {
        this._drawScrollbar();
    }
    _handleEvent(event) {
        var [x, y] = this._eventToXY(event);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                if (this.scrollbar.checkEvent(event)) {
                    if (this.scrollbar.isInside(x, y)) {
                        this._scrollbarPressed(event);
                    }
                }
                else {
                    this._scrollbar_pressed = false;
                }
                if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
                    if (y < this.scrollbar.ypixel && y > this.ypixel) {
                        this._scroll_position -= this._rows_per_page;
                        redraw = true;
                        this._has_changed = true;
                    }
                    else if (y > this.scrollbar.ypixel + this.scrollbar.heightpixel && y < this.ypixel + this.heightpixel) {
                        this._scroll_position += this._rows_per_page;
                        redraw = true;
                        this._has_changed = true;
                    }
                    this._getScrollbarYPos();
                }
                break;
            case "mousemove":
                if (this._mouse_down && this._scrollbar_pressed) {
                    var prev_scroll_position = this._scroll_position;
                    this._scroll_position = Math.floor((y - this._mouse_down_scrollbar_ypos - this.ypixel) / this.pixels_per_row);
                    this._getScrollbarYPos();
                    if (this._scroll_position != prev_scroll_position) {
                        redraw = true;
                        this._has_changed = true;
                    }
                }
                break;
        }
        if (redraw && this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
        return this._has_changed;
    }
    set rows(rows) {
        if (rows == 0) {
            rows = 1;
        }
        this._rows = rows;
    }
    get rows() {
        return this._rows;
    }
    set rows_per_page(rows_per_page) {
        this._rows_per_page = rows_per_page;
    }
    get rows_per_page() {
        return this._rows_per_page;
    }
    set scroll_position(scroll_position) {
        this._scroll_position = scroll_position;
    }
    get scroll_position() {
        return this._scroll_position;
    }
}
//# sourceMappingURL=cxscrollbar.js.map