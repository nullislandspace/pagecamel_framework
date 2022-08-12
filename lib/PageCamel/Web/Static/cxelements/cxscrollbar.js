class CXScrollBar extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);

        this.box_color = "white";
        this.scrollbar = new CXBox(ctx, 0.0, 0.0, 1.0, 1.0, true, false);
        this.scrollbar.box_color = "black";

        this.rows = 1;
        this.rows_per_page = 1;
        this.scroll_position = 0;

        this.pixels_per_page = this.heightpixel / this.rows_per_page;
        this.pixels_per_row = this.heightpixel / this.rows;
    }
    _drawScrollbar() {
        this.scrollbar._height = this._getScrollbarHeight();
        this.scrollbar._ypos = this._getScrollbarYPos();
        super._draw();
        this.scrollbar.draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
    }
    _getScrollbarYPos() {
        this.scroll_position = Math.max(0, Math.min(this.scroll_position, this.rows - this.rows_per_page)); // make sure the scroll position is within the bounds of the scrollbar
        return this._ypos + this.pixels_per_row * this.scroll_position; // calculate the y position of the scrollbar
    }
    _getScrollbarHeight() {
        //calcualtes the height of the scrollbar depending on the amount of rows 
        this.pixels_per_page = this.heightpixel / this.rows_per_page;
        this.pixels_per_row = this.heightpixel / this.rows;
        if (this.rows > this.rows_per_page) {
            return this.heightpixel / (this.rows / this.rows_per_page);
        }
        return this.heightpixel;
    }
    _draw() {
        this._drawScrollbar();
    }
    _scrollbarPressed(event) {
        var [x, y] = this._eventToXY(event);
        this.mouse_down_scrollbar_ypos = y - this.scrollbar.ypixel; // the y position of the mouse relative to the y position of the scrollbar
        this.mouse_down = true;

    }
    handleEvent(event, callback) {
        var [x, y] = this._eventToXY(event);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                if (this.scrollbar.checkEvent(event)) {
                    this.scrollbar.handleEvent(event, this._scrollbarPressed.bind(this));
                    redraw = true;
                }
                if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
                    if (y < this.scrollbar.ypixel && y > this.ypixel) {
                        // jump one page up                
                        this.scroll_position -= this.rows_per_page;
                        redraw = true;
                    }
                    else if (y > this.scrollbar.ypixel + this.scrollbar.heightpixel && y < this.ypixel + this.heightpixel) {
                        // jump one page down
                        this.scroll_position += this.rows_per_page;
                        redraw = true;
                    }
                }
                break;
            case "mousemove":
                if (this.mouse_down) {
                    this.scroll_position = Math.floor((y - this.mouse_down_scrollbar_ypos - this.ypixel) / this.pixels_per_row);
                    redraw = true;
                }
                break;
            case "mouseup":
                if (this.mouse_down) {
                    this.mouse_down = false;
                }
                break;
        }
        if (redraw && this._redraw) {
            this._draw();
        }
    }
}