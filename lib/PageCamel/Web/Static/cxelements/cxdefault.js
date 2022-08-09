class CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true) {

        this.ctx = ctx;
        this.is_relative = is_relative;

        this._xpos = this._calcRelToPixel(x).x;
        this._ypos = this._calcRelToPixel(0, y).y;
        this._width = this._calcRelToPixel(width).x;
        this._height = this._calcRelToPixel(0, height).y;
    }
    draw(/*xp = 0, yp = 0, width, height*/) {
        /*this.ctx.save();
        if(this.is_relative) {
            var xpixel = this._calcRelToPixel(xp).x;
            var ypixel = this._calcRelToPixel(yp).y;
        }
        this.ctx.translate(xpixel, ypixel);
        this.ctx.restore();*/
    }
    _calcRelToPixel(rel_x = 0, rel_y = 0) {
        var x = rel_x;
        var y = rel_y;
        if (this.is_relative) {
            // calculate the x position of the element relative to the canvas
            if (!isNaN(parseFloat(rel_x)) && rel_x >= 0 && rel_x <= 1) {
                x = rel_x * this.ctx.canvas.width;
            }
            // calculate the y position of the element relative to the canvas
            if (!isNaN(parseFloat(rel_y)) && rel_y >= 0 && rel_y <= 1) {
                y = rel_y * this.ctx.canvas.height;
            }
        }
        return { x, y };
    }
    /**
     * @param {number | undefined} width
     */
    set width(width) {
        this._width = this._calcRelToPixel(width).x;
    }
    get width() {
        return this._width;
    }
    /**
     * @param {number | undefined} height
     */
    set height(height) {
        this._height = this._calcRelToPixel(0, height).y;
    }
    get height() {
        return this._height;
    }
    /**
     * @param {number | undefined} x
     */
    set xpos(x) {
        this._xpos = this._calcRelToPixel(x).x;
    }
    get xpos() {
        return this._xpos;
    }
    /**
     * @param {number | undefined} y
     */
    set ypos(y) {
        this._ypos = this._calcRelToPixel(0, y).y;
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