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
    _checkMouseMove(x, y) {
        // check if the mouse is over the element or there is a mouse out event or a mouse in event to handle
        var return_value = false;
        if (this._mouse_down) {
            return_value = true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            if (!this._mouse_over) {
                this._mouse_in = true;
                this._mouse_out = false;
                return_value = true;
            }
            else if (this._mouse_in) {
                this._mouse_in = false;
            }
            this._mouse_over = true;
        }
        else {
            if (this._mouse_over) {
                this._mouse_out = true;
                this._mouse_in = false;
                return_value = true;
            }
            else if (this._mouse_out) {
                this._mouse_out = false;
            }
            this._mouse_over = false;
        }
        return return_value;
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
                if (this._mouse_down) {
                    this.scroll_position = Math.floor((y - this.mouse_down_scrollbar_ypos - this.ypixel) / this.pixels_per_row);
                    redraw = true;
                }
                break;
        }
        if (redraw && this._redraw) {
            this._draw();
        }
    }
}