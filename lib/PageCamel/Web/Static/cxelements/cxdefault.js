class CXDefault {
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
    */
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        this._ctx = ctx;
        this._is_relative = is_relative;

        this._elements = [];

        this._xpos = x;
        this._ypos = y;
        this._width = width;
        this._height = height;

        this._redraw = redraw;

        this._xpixel = 0;
        this._ypixel = 0;
        this._widthpixel = 0;
        this._heightpixel = 0;

        this._mouse_down = false;
        this._mouse_over = false;
        this._mouse_in = false;
        this._mouse_out = false;

        this._has_changed = false;
    }
    /**
     * @param {number} px - x position of the element in pixels
     * @param {number} py - y position of the element in pixels
     * @param {number} pwidth - width of the element in pixels
     * @param {number} pheight - height of the element in pixels
     */
    draw(px = 0, py = 0, pwidth = this._ctx.canvas.width, pheight = this._ctx.canvas.height) {
        var [xpixel, ypixel, widthpixel, heightpixel] = this._calcRelativePositions(px, py, pwidth, pheight);
        this.xpixel = xpixel;
        this.ypixel = ypixel;
        this.widthpixel = widthpixel;
        this.heightpixel = heightpixel;
        if (this._redraw) {
            this._ctx.clearRect(xpixel, ypixel, widthpixel, heightpixel);
            this._ctx.fillStyle = "white";
            this._ctx.fillRect(xpixel, ypixel, widthpixel, heightpixel);
        }
        this._has_changed = false;
        this._draw()
    }
    /**
     * @param {event} event - the event to get the mouse position from
     * @returns {Array} [x, y] - the mouse position relative to the canvas
     * @protected - should only be called by the child class
     */
    _eventToXY(event) {
        var x = event.offsetX;
        var y = event.offsetY;
        return [x, y];
    }
    _draw() {
        // override this function in child classes to draw the element
    }
    _calcRelXToPixel(rel_x = 0, max_width = this._ctx.canvas.width) {
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
    _calcRelYToPixel(rel_y = 0, max_height = this._ctx.canvas.height) {
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
    /**
     * @protected - should only be called by the child class
     */
    _calcRelativePositions(px, py, pwidth, pheight) {
        var xpixel = px + this._calcRelXToPixel(this._xpos, pwidth);
        var ypixel = py + this._calcRelYToPixel(this._ypos, pheight);
        var widthpixel = this._calcRelXToPixel(this._width, pwidth);
        var heightpixel = this._calcRelYToPixel(this._height, pheight);
        return [xpixel, ypixel, widthpixel, heightpixel];
    }
    /**
     * @param {number} width
     * @public - accessible from outside the class
     */
    set width(width) {
        this._width = this._calcRelXToPixel(width);
    }
    get width() {
        return this._width;
    }
    /**
     * @param {number} height
     * @public - accessible from outside the class
     */
    set height(height) {
        this._height = this._calcRelYToPixel(height);
    }
    get height() {
        return this._height;
    }
    /**
     * @param {number} x
     * @public - accessible from outside the class
     */
    set xpos(x) {
        this._xpos = this._calcRelXToPixel(x);
    }
    get xpos() {
        return this._xpos;
    }
    /**
     * @param {number} y
     * @public - accessible from outside the class
     */
    set ypos(y) {
        this._ypos = this._calcRelYToPixel(y);
    }
    get ypos() {
        return this._ypos;
    }
    /**
     * @param {boolean} state
     * @public - accessible from outside the class
     */
    set is_relative(state) {
        this._is_relative = state;
    }
    get is_relative() {
        return this._is_relative;
    }
    /**
     * @param {CanvasRenderingContext2D} value
     * @public - accessible from outside the class
     */
    set ctx(value) {
        this._ctx = value;
    }
    get ctx() {
        return this._ctx;
    }
    /**
     * @param {boolean} changed
     */
    set has_changed(changed) {
        this._has_changed = changed;
    }
    get has_changed() {
        return this._has_changed;
    }

    _getViewInfo() {
    }
    _getMinSize() {
    }
    _getMaxSize() {
    }
    _checkEvent(event) {
        var [mouse_x, mouse_y] = this._eventToXY(event);
        switch (event.type) {
            case 'click':
                return this._checkClick(mouse_x, mouse_y);
            case 'mousemove':
                return this._checkMouseMove(mouse_x, mouse_y);
            case 'mousedown':
                return this._checkMouseDown(mouse_x, mouse_y);
            case 'mouseup':
                return this._checkMouseUp(mouse_x, mouse_y);
            case 'mouseleave':
                return this._checkMouseLeave(mouse_x, mouse_y);
        }
        return false;
    }
    /**
     * @param {event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    checkEvent(event) {
        /* check if the event is affecting the element and if so return true
           else return false
           */
        return this._checkEvent(event);

    }
    _checkClick(x, y) {
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            return true;
        }
        return false;
    }
    _checkMouseDown(x, y) {
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this._mouse_down = true;
            return true;
        }
        this._mouse_down = false;
        return false;
    }
    _checkMouseMove(x, y) {
        // check if the mouse is over the element or there is a mouse out event or a mouse in event to handle
        var return_value = false;
        if (this._mouse_down) {
            return_value = true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            if (!this._mouse_over) {
                return_value = true;
            }
            this._mouse_over = true;
        }
        else {
            if (this._mouse_over) {
                return_value = true;
            }
            this._mouse_over = false;
        }
        return return_value;
    }
    _checkMouseUp(x, y) {
        if (this._mouse_down) {
            this._mouse_down = false;
            return true;
        }
        return false;
    }
    _checkMouseLeave(x, y) {
        this._mouse_down = false;
        this._mouse_over = false;
        this._mouse_in = false;
        this._mouse_out = false;
        return true;
    }
    handleEvent(event, callback) {
        // either override this function in child classes or give a custom callback function to handle events
        if (callback) {
            callback(event);
        }
    }
}