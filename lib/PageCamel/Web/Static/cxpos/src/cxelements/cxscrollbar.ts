import { CXBox } from "./cxbox.js";
export class CXScrollBar extends CXBox {
    /** @protected */
    protected scrollbar: CXBox;
    /** @protected */
    protected _rows: number;
    /** @protected */
    protected _rows_per_page: number;
    /** @protected */
    protected _scroll_position: number;
    /** @protected */
    protected pixels_per_row: number;
    /** @protected */
    protected _scrollbar_pressed: boolean;
    protected _mouse_down_scrollbar_ypos: number;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean, redraw: boolean) {
        super(ctx, x, y, width, height, is_relative, redraw);

        this._mouse_down_scrollbar_ypos = 0;

        /** @protected */
        this.background_color = "white";
        /** @protected */
        this.scrollbar = new CXBox(ctx, 0.0, 0.0, 1.0, 1.0, true, false);
        this.scrollbar.background_color = "black";
        this.scrollbar.border_width = 0;


        /** @protected */
        this._rows = 1;
        /** @protected */
        this._rows_per_page = 1;
        /** @protected */
        this._scroll_position = 0;

        /** @protected */
        this.pixels_per_row = this.heightpixel / this._rows;

        /** @protected */
        this._scrollbar_pressed = false;

        /** @protected */
        this._name = "CXScrollBar";
    }
    /**
     * @protected
     */
    protected _drawScrollbar() {
        this.scrollbar.height = this._getScrollbarHeight();
        this.scrollbar.ypos = this._getScrollbarYPos();
        super._draw();
        this.scrollbar.draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
    }
    /**
     * @description sets the scroll position
     * @returns {number} the y position of the scrollbar
     * @protected
     */
    protected _getScrollbarYPos(): number {
        this._scroll_position = Math.max(0, Math.min(this._scroll_position, this._rows - this._rows_per_page)); // make sure the scroll position is within the bounds of the scrollbar
        return 1 / this._rows * this._scroll_position; // calculate the y position of the scrollbar
    }
    /**
     * @protected
     * @returns {number} the height of the scrollbar between 0 and 1
     * @description calculates the height of the scrollbar
     */
    protected _getScrollbarHeight(): number {
        //calcualtes the height of the scrollbar depending on the amount of rows 
        this.pixels_per_row = this.heightpixel / this._rows;
        if (this._rows > this._rows_per_page) {
            var height = 1 / (this._rows / this._rows_per_page);
            return height;
        }
        return 1;
    }
    /**
     * @protected
     */
    protected _draw() {
        this._drawScrollbar();
    }
    /**
     * @param {event} event
     * @protected
     * @description handles the mouse down event on the scrollbar
     */
    protected _scrollbarPressed = (event: MouseEvent) => {
        var [x, y] = this._eventToXY(event);
        this._mouse_down_scrollbar_ypos = y - this.scrollbar.ypixel; // the y position of the mouse relative to the y position of the scrollbar
        this._scrollbar_pressed = true;
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    protected _handleEvent(event: Event): boolean {
        var [x, y] = this._eventToXY(event as MouseEvent);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                if (this.scrollbar.checkEvent(event)) {
                    if (this.scrollbar.isInside(x, y)) {
                        this._scrollbarPressed(event as MouseEvent);
                    }
                }
                else {
                    this._scrollbar_pressed = false;
                }
                if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
                    if (y < this.scrollbar.ypixel && y > this.ypixel) {
                        // jump one page up                
                        this._scroll_position -= this._rows_per_page;
                        redraw = true;
                        this._has_changed = true;
                    }
                    else if (y > this.scrollbar.ypixel + this.scrollbar.heightpixel && y < this.ypixel + this.heightpixel) {
                        // jump one page down
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
    /**
     * @param {number} rows
     */
    set rows(rows: number) {
        if (rows == 0) {
            rows = 1;
        }
        this._rows = rows;
    }
    get rows(): number {
        return this._rows;
    }
    /**
     * @param {number} rows_per_page
     */
    set rows_per_page(rows_per_page: number) {
        this._rows_per_page = rows_per_page;
    }
    get rows_per_page(): number {
        return this._rows_per_page;
    }
    set scroll_position(scroll_position: number) {
        this._scroll_position = scroll_position;
    }
    get scroll_position(): number {
        return this._scroll_position;
    }
}