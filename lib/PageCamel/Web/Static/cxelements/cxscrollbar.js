class CXScrollBar extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);

        this.box_color = "white";
        this.scrollbar = new CXBox(ctx, 0.0, 0.0, 1.0, 1.0, true, false);
        this.scrollbar.box_color = "black";
        this.scrollbar._border_width = 0;


        this._rows = 1;
        this._rows_per_page = 1;
        this.scroll_position = 0;

        this.pixels_per_page = this.heightpixel / this._rows_per_page;
        this.pixels_per_row = this.heightpixel / this._rows;
    }
    _drawScrollbar() {
        this.scrollbar._height = this._getScrollbarHeight();
        this.scrollbar._ypos = this._getScrollbarYPos();
        super._draw();
        this.scrollbar.draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
    }
    _getScrollbarYPos() {
        this.scroll_position = Math.max(0, Math.min(this.scroll_position, this._rows - this._rows_per_page)); // make sure the scroll position is within the bounds of the scrollbar
        return this._ypos + this.pixels_per_row * this.scroll_position; // calculate the y position of the scrollbar
    }
    _getScrollbarHeight() {
        //calcualtes the height of the scrollbar depending on the amount of rows 
        this.pixels_per_page = this.heightpixel / this._rows_per_page;
        this.pixels_per_row = this.heightpixel / this._rows;
        if (this._rows > this._rows_per_page) {
            var height = this.heightpixel / (this._rows / this._rows_per_page);
            return height;
        }
        return this.heightpixel;
    }
    _draw() {
        this._drawScrollbar();
    }
    _scrollbarPressed(event) {
        var [x, y] = this._eventToXY(event);
        this.mouse_down_scrollbar_ypos = y - this.scrollbar.ypixel; // the y position of the mouse relative to the y position of the scrollbar
    }
    handleEvent(event) {
        var [x, y] = this._eventToXY(event);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                if (this.scrollbar.checkEvent(event)) {
                    this.scrollbar.handleEvent(event, this._scrollbarPressed.bind(this));
                }
                if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
                    if (y < this.scrollbar.ypixel && y > this.ypixel) {
                        // jump one page up                
                        this.scroll_position -= this._rows_per_page;
                        redraw = true;
                        this._has_changed = true;
                    }
                    else if (y > this.scrollbar.ypixel + this.scrollbar.heightpixel && y < this.ypixel + this.heightpixel) {
                        // jump one page down
                        this.scroll_position += this._rows_per_page;
                        redraw = true;
                        this._has_changed = true;
                    }
                }
                break;
            case "mousemove":
                if (this._mouse_down) {
                    this.prev_scroll_position = this.scroll_position;
                    this.scroll_position = Math.floor((y - this.mouse_down_scrollbar_ypos - this.ypixel) / this.pixels_per_row);
                    this._getScrollbarYPos();
                    if (this.scroll_position != this.prev_scroll_position) {
                        redraw = true;
                        this._has_changed = true;
                    }
                }
                break;
        }
        if (redraw && this._redraw) {
            this._draw();
        }
    }
    /**
     * @param {number} rows
     */
    set rows(rows) {
        if(rows == 0) {
            rows = 1;
        }
        this._rows = rows;
    }
    get rows() {
        return this._rows;
    }
    /**
     * @param {number} rows_per_page
     */
    set rows_per_page(rows_per_page) {
        this._rows_per_page = rows_per_page;
    }
    get rows_per_page() {
        return this._rows_per_page;
    }
}