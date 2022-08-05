class CXScrollBar extends CXBox {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.arrow_button_height = width;

        this.up_arrow = new CXArrowButton(ctx, x, y, width, this.arrow_button_height);
        this.down_arrow = new CXArrowButton(ctx, x, y + height - this.arrow_button_height, width, this.arrow_button_height);

        this.box_color = "white";

        this.scrollbar_height = height - this.arrow_button_height * 2;
        this.scrollbar = new CXBox(ctx, x, y + this.arrow_button_height, width, this.scrollbar_height);
        this.scrollbar.box_color = "black";

        this.up_arrow.arrow_direction = "up";
        this.down_arrow.arrow_direction = "down";

        this.rows = 1;
        this.rows_per_page = 1;
        this.scroll_position = 0;
    }
    _drawScrollbar() {
        this.scrollbar.height = this._getScrollbarHeight();
        this._drawBox();
        this.up_arrow.draw();
        this.down_arrow.draw();
        this.scrollbar.draw();
    }
    _getScrollbarHeight() {
        //calcualtes the height of the scrollbar depending on the amount of rows 
        if (this.rows > this.rows_per_page) {
            return this.scrollbar_height / (this.rows / this.rows_per_page);
        }
        //this.pixels_per_row = this.scrollbar_height / this.rows_per_page;
        return this.scrollbar_height;
    }
    draw() {
        this._drawScrollbar();
    }
    checkMouseDown(x, y) {
        // check if the mouse is inside the scrollbar
        if (x >= this.xpos && x <= this.xpos + this.width && y >= this.ypos + this.arrow_button_height && y <= this.ypos + this.height - this.arrow_button_height) {
            this.mouseDownHandler(x, y);
        }
    }
    mouseDownHandler(x, y) {


    }
    checkMouseMove(x, y) {

    }

}