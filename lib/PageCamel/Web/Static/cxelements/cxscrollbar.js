class CXScrollBar extends CXBox {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);

        this.box_color = "white";
        this.scrollbar = new CXBox(ctx, x, y, width, height);
        this.scrollbar.box_color = "black";

        this.rows = 1;
        this.rows_per_page = 1;
        this.scroll_position = 0;

        this.pixels_per_page = height / this.rows_per_page;
        this.pixels_per_row = height / this.rows;
    }
    _drawScrollbar() {
        this.scrollbar.width = this.width;
        this.scrollbar.x = this.xpos;
        this.scrollbar.height = this._getScrollbarHeight();
        this.scrollbar.ypos = this._getScrollbarYPos();
        this._drawBox();
        this.scrollbar.draw();
    }
    _getScrollbarYPos() {
        this.scroll_position = Math.max(0, Math.min(this.scroll_position, this.rows - this.rows_per_page)); // make sure the scroll position is within the bounds of the scrollbar
        return this.ypos + this.pixels_per_row * this.scroll_position; // calculate the y position of the scrollbar
    }
    _getScrollbarHeight() {
        //calcualtes the height of the scrollbar depending on the amount of rows 
        this.pixels_per_page = this.height / this.rows_per_page;
        this.pixels_per_row = this.height / this.rows;
        if (this.rows > this.rows_per_page) {
            return this.height / (this.rows / this.rows_per_page);
        }
        return this.height;
    }
    draw() {
        this._drawScrollbar();
    }
    checkMouseDown(x, y) {
        // check if the mouse is inside the scrollbar
        if (x >= this.xpos && x <= this.xpos + this.width && y >= this.ypos && y <= this.ypos + this.height) {
            this.mouseDownHandler(x, y);
        }
    }
    mouseDownHandler(x, y) {
        if (y >= this.scrollbar.ypos && y <= this.scrollbar.ypos + this.scrollbar.height && x >= this.xpos && x <= this.xpos + this.width) {
            this.mouse_down_scrollbar_ypos = y - this.scrollbar.ypos; // the y position of the mouse relative to the y position of the scrollbar
            this.mouse_down = true;
            console.log("mouse down");
        }
        else if (y < this.scrollbar.ypos && y > this.ypos) {
            // jump one page up
            this.scroll_position -= this.rows_per_page;
            triggerRepaint();
        }
        else if (y > this.scrollbar.ypos + this.scrollbar.height && y < this.ypos + this.height) {
            // jump one page down
            this.scroll_position += this.rows_per_page;
            triggerRepaint();
        }

    }
    checkMouseMove(x, y) {
        if (this.mouse_down) {
            this.mouseMoveHandler(x, y);
        }
    }
    mouseMoveHandler(x, y) {
        this.scroll_position = Math.floor((y - this.mouse_down_scrollbar_ypos - this.ypos) / this.pixels_per_row); 
        triggerRepaint();
    }
    checkMouseUp(x, y) {
        if (this.mouse_down) {
            this.mouseUpHandler(x, y);
        }
    }
    mouseUpHandler(x, y) {
        this.mouse_down = false;
    }
}