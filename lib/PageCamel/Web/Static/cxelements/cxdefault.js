export class CXDefault {
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
    */
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        /** @protected  */
        this._ctx = ctx;
        /** @protected  */
        this._is_relative = is_relative;
        /** @protected  */
        this._elements = [];
        /** @protected  */
        this._xpos = x;
        /** @protected  */
        this._ypos = y;
        /** @protected  */
        this._width = width;
        /** @protected  */
        this._height = height;
        /** @protected  */
        this._redraw = redraw;
        /** @protected  */
        this._xpixel = 0;
        /** @protected  */
        this._ypixel = 0;
        /** @protected  */
        this._widthpixel = 0;
        /** @protected  */
        this._heightpixel = 0;
        /** @protected  */
        this._mouse_down = false;
        /** @protected  */
        this._mouse_over = false;
        /** @protected  */
        this._has_changed = false;
        /** @protected  */
        this._takes_keyboard_input = false;
        /** @protected  */
        this._active = true;
        /** @protected  */
        this._px = 0;
        /** @protected  */
        this._py = 0;
        /** @protected  */
        this._pwidth = 0;
        /** @protected  */
        this._pheight = 0;
        /** @protected  */
        this._name = 'CXDefault';
    }
    /**code to calculate the relative positions of the element
     * @param {number} px - x position of the element in pixels
     * @param {number} py - y position of the element in pixels
     * @param {number} pwidth - width of the element in pixels
     * @param {number} pheight - height of the element in pixels
     */
    draw(px = 0, py = 0, pwidth = this._ctx.canvas.width, pheight = this._ctx.canvas.height) {
        this._px = px;
        this._py = py;
        this._pwidth = pwidth;
        this._pheight = pheight;

        var [xpixel, ypixel, widthpixel, heightpixel] = this._calcRelativePositions(px, py, pwidth, pheight);
        this._xpixel = xpixel;
        this._ypixel = ypixel;
        this._widthpixel = widthpixel;
        this._heightpixel = heightpixel;
        this._convertToPixel();
        if (this._redraw) {
            this._clear();
        }
        this._has_changed = false;
        if (this._active) {
            this._checkOverflow(this._xpos, this._ypos, this._width, this._height);
            this._draw();
        }
    }
    /** 
     * @protected   
     * @description Converts the relative position to pixel position
    */
    _convertToPixel() {
        // override this function in child classes to convert the relative position to pixel position
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
    /** @protected  */
    _clear() {
        if (this._redraw) {
            this._ctx.clearRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
            this._ctx.fillStyle = "#b3b3b3ff";
            this._ctx.fillRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        }
    }
    /** @protected  */
    _tryRedraw(px = 0, py = 0, pwidth = this._ctx.canvas.width, pheight = this._ctx.canvas.height) {
        if (this._redraw && this._has_changed) {
            this.draw(px, py, pwidth, pheight);
        }
    }
    /** @protected  */
    _draw() {
        // override this function in child classes to draw the element
    }
    /** @protected  */
    _calcRelXToPixel(rel_x = 0, max_width = this._ctx.canvas.width) {
        /* rel_x = relative position | size to convert to pixel position | max_width = pixel width of the area to draw in */
        var x = rel_x;
        if (this._is_relative) {
            // calculate the x position of the element relative to the canvas
            if (!isNaN(parseFloat(rel_x))) {
                x = rel_x * max_width;
            }
        }
        return x;
    }
    /** @protected  */
    _calcRelYToPixel(rel_y = 0, max_height = this._ctx.canvas.height) {
        /* rel_y = relative position | size to convert to pixel position | max_height = pixel height of the area to draw in */
        var y = rel_y;
        if (this._is_relative) {
            // calculate the y position of the element relative to the canvas
            if (!isNaN(parseFloat(rel_y))) {
                y = rel_y * max_height;
            }
        }
        return y;
    }
    /**
     * @protected - should only be called by the child class
     */
    _calcRelativePositions(px, py, pwidth, pheight) {
        var xpixel = Math.floor(px + this._calcRelXToPixel(this._xpos, pwidth));
        var ypixel = Math.floor(py + this._calcRelYToPixel(this._ypos, pheight));
        var widthpixel = Math.ceil(this._calcRelXToPixel(this._width, pwidth));
        var heightpixel = Math.ceil(this._calcRelYToPixel(this._height, pheight));
        return [xpixel, ypixel, widthpixel, heightpixel];
    }
    /** @protected  */
    _getViewInfo() {
    }
    /** @protected  */
    _getMinSize() {
    }
    /** @protected  */
    _getMaxSize() {
    }
    /** @protected  */
    _checkEvent(event) {
        var [mouse_x, mouse_y] = this._eventToXY(event);
        if (this._active) {
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
                case 'keydown':
                    return this._checkKeyDown(event);
                case 'keyup':
                    return this._checkKeyUp(event);
            }
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
    /** @protected  */
    _checkClick(x, y) {
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            return true;
        }
        return false;
    }
    /** @protected  */
    _checkMouseDown(x, y) {
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            this._mouse_down = true;
            return true;
        }
        this._mouse_down = false;
        return false;
    }
    /** @protected  */
    _checkMouseMove(x, y) {
        if (this._mouse_down) {
            return true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this._mouse_over = true;
            return true;
        } else if (this._mouse_over) {
            this._mouse_over = false;
            return true;
        }
        return false;
    }
    /** @protected  */
    _checkMouseUp(x, y) {
        if (this._mouse_down) {
            this._mouse_down = false;
            return true;
        }
        return false;
    }
    /** @protected  */
    _checkMouseLeave(x, y) {
        this._mouse_down = false;
        this._mouse_over = false;
        return true;
    }
    /** @protected  */
    _checkKeyDown() {

        if (this._takes_keyboard_input) {
            return true;
        }
        return false;
    }
    /** @protected  */
    _checkKeyUp() {
        if (this._takes_keyboard_input) {
            return true;
        }
        return false;
    }
    /**
     * @param {event} event - the event to check
     * @param {callback} function
     * @returns {boolean} - if the event needs to be handled
     */
    handleEvent(event, callback) {
        // either override this function in child classes or give a custom callback function to handle events
        if (callback) {
            callback(event);
        }
    }
    /** @protected  */
    _checkOverflow(x, y, width, height) {
        if (this._is_relative) {
            if (x < 0 || x > 1 || y < 0 || y > 1) {
                console.warn("Position is outside drawing area");
            }
            if (x + width > 1 || y + height > 1) {
                console.warn("Position and size is outside drawing area");
            }
        } else {
            if (x < 0 || x > this._ctx.canvas.width || y < 0 || y > this._ctx.canvas.height) {
                console.warn("Position is outside drawing area");
            }
            if (x + width > this._ctx.canvas.width || y + height > this._ctx.canvas.height) {
                console.warn("Position and size is outside drawing area");
            }
        }
        return false;
    }
    /**
    * @param {number} width
    * @public - accessible from outside the class
    */
    set width(width) {
        this._width = width;
    }
    get width() {
        return this._width;
    }
    /**
     * @param {number} height
     * @public - accessible from outside the class
     */
    set height(height) {
        this._height = height;
    }
    get height() {
        return this._height;
    }
    /**
     * @param {number} x
     * @public - accessible from outside the class
     */
    set xpos(x) {
        this._xpos = x;
    }
    get xpos() {
        return this._xpos;
    }
    /**
     * @param {number} y
     * @public - accessible from outside the class
     */
    set ypos(y) {
        this._ypos = y;
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
    get xpixel() {
        return this._xpixel;
    }
    get ypixel() {
        return this._ypixel;
    }
    get widthpixel() {
        return this._widthpixel;
    }
    get heightpixel() {
        return this._heightpixel;
    }
    /**
     * @param {boolean} state - if the element is visible or not
     */
    set active(state) {
        this._active = state;
    }
    get active() {
        return this._active;
    }
    /**
     * @param {string} name - the name of the element
     */
    set name(name) {
        this._name = name;
    }
    get name() {
        return this._name;
    }
}