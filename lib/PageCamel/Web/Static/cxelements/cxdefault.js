class CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true) {

        this.ctx = ctx;
        this.is_relative = is_relative;

        this._xpos = x;
        this._ypos = y;
        this._width = width;
        this._height = height;
    }
    draw(px = 0, py = 0, pwidth = this.ctx.canvas.width, pheight = this.ctx.canvas.height) {
        var [xpixel, ypixel, widthpixel, heightpixel] = this._calcRelativePositions(px, py, pwidth, pheight);
        this._draw(xpixel, ypixel, widthpixel, heightpixel);
    }
    _draw(xpixel, ypixel, widthpixel, heightpixel) {
        // override this function in child classes to draw the element
    }
    _calcRelXToPixel(rel_x = 0, max_width = this.ctx.canvas.width) {
        /* rel_x = relative position | size to convert to pixel position | max_width = pixel width of the area to draw in */
        var x = rel_x;
        if (this.is_relative) {
            // calculate the x position of the element relative to the canvas
            if (!isNaN(parseFloat(rel_x)) && rel_x >= 0 && rel_x <= 1) {
                x = rel_x * max_width;
            }
        }
        return x;
    }
    _calcRelYToPixel(rel_y = 0, max_height = this.ctx.canvas.height) {
        /* rel_y = relative position | size to convert to pixel position | max_height = pixel height of the area to draw in */
        var y = rel_y;
        if (this.is_relative) {
            // calculate the y position of the element relative to the canvas
            if (!isNaN(parseFloat(rel_y)) && rel_y >= 0 && rel_y <= 1) {
                y = rel_y * max_height;
            }
        }
        return y;
    }
    _calcRelativePositions(px, py, pwidth, pheight) {
        var xpixel = px + this._calcRelXToPixel(this._xpos, pwidth);
        var ypixel = py + this._calcRelYToPixel(this._ypos, pheight);
        var widthpixel = this._calcRelXToPixel(this._width, pwidth);
        var heightpixel = this._calcRelYToPixel(this._height, pheight);
        return [xpixel, ypixel, widthpixel, heightpixel];
    }
    /**
     * @param {number | undefined} width
     */
    set width(width) {
        this._width = this._calcRelXToPixel(width);
    }
    get width() {
        return this._width;
    }
    /**
     * @param {number | undefined} height
     */
    set height(height) {
        this._height = this._calcRelYToPixel(height);
    }
    get height() {
        return this._height;
    }
    /**
     * @param {number | undefined} x
     */
    set xpos(x) {
        this._xpos = this._calcRelXToPixel(x);
    }
    get xpos() {
        return this._xpos;
    }
    /**
     * @param {number | undefined} y
     */
    set ypos(y) {
        this._ypos = this._calcRelYToPixel(y);
    }
    get ypos() {
        return this._ypos;
    }
    _getViewInfo() {
    }
    _getMinSize() {
    }
    _getMaxSize() {
    }



    checkClick(x, y) {
        // check if mouse click is inside the frame 
        if (x >= this._xpos && x <= this._xpos + this._width && y >= this._ypos && y <= this._ypos + this._height) {
            this.clickHandler();
        }
    }
    checkMouseDown(x, y) {
        // check if mouse down is inside the frame
        if (x >= this._xpos && x <= this._xpos + this._width && y >= this._ypos && y <= this._ypos + this._height) {
            this.mouseDownHandler();
        }
    }
    checkMouseMove(x, y) {
        // check if mouse is inside the frame
        if (!this.hovering && x >= this._xpos && x <= this._xpos + this._width && y >= this._ypos && y <= this._ypos + this._height) {
            this.mouseInHandler();
            this.hovering = true;
        } else if (this.hovering && (x < this._xpos || x > this._xpos + this._width || y < this._ypos || y > this._ypos + this._height)) {
            this.mouseOutHandler();
            this.hovering = false;
        }

    }
    checkMouseUp(x, y) {
        // check if mouse up is inside the frame
        if (x >= this._xpos && x <= this._xpos + this._width && y >= this._ypos && y <= this._ypos + this._height) {
            this.mouseUpHandler();
        }
    }
    mouseUpHandler() {
        // override this function in child classes to handle mouse up events
    }
    clickHandler() {
        // override this function in child classes to handle click events
    }
    mouseInHandler() {
        // override this function in child classes to handle hover events
    }
    mouseOutHandler() {
        // override this function in child classes to handle hover out events
    }
    mouseDownHandler() {
        // override this function in child classes to handle mouse down events
    }
}