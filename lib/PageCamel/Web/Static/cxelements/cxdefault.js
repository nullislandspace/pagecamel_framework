class CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true) {

        this.ctx = ctx;
        this.is_relative = is_relative;

        this.elements = [];

        this._xpos = x;
        this._ypos = y;
        this._width = width;
        this._height = height;

        this.xpixel = 0;
        this.ypixel = 0;
        this.widthpixel = 0;
        this.heightpixel = 0;

        this.hovering = false;
    }
    draw(px = 0, py = 0, pwidth = this.ctx.canvas.width, pheight = this.ctx.canvas.height) {
        var [xpixel, ypixel, widthpixel, heightpixel] = this._calcRelativePositions(px, py, pwidth, pheight);
        this.xpixel = xpixel;
        this.ypixel = ypixel;
        this.widthpixel = widthpixel;
        this.heightpixel = heightpixel;
        this._draw()
    }
    _eventToXY(event) {
        var x = event.pageX - qcanvas.offset().left;
        var y = event.pageY - qcanvas.offset().top;
        return [x, y];
    }
    _draw() {
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
    _checkEvent(event) {
        var mouse_x = Math.floor((event.pageX - qcanvas.offset().left));
        var mouse_y = Math.floor((event.pageY - qcanvas.offset().top));
        switch (event.type) {
            case 'click':
                return this.checkClick(mouse_x, mouse_y);
            case 'mousemove':
                return this.checkMouseMove(mouse_x, mouse_y);
            case 'mousedown':
                return this.checkMouseDown(mouse_x, mouse_y);
            case 'mouseup':
                return this.checkMouseUp(mouse_x, mouse_y);
        }
        return false;
    }
    checkEvent(event, custom_check_function) {
        /* check if the event is affecting the element and if so return true
           else return false
            custom_check_function = function(event) { return true/false }
            if custom_check_function is defined, it will be used instead of the default check function
           */
        if (custom_check_function) {
            return custom_check_function(event);
        }
        return this._checkEvent(event);

    }
    checkClick(x, y) {
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this.clickHandler(x, y);
            return true;
        }
        return false;
    }
    checkMouseDown(x, y) {
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this.mouseDownHandler(x, y);
            return true;
        }
        return false;
    }
    checkMouseMove(x, y) {
        if (!this.hovering && x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this.mouseInHandler(x, y);
            this.hovering = true;
        } else if (this.hovering && (x < this.xpixel || x > this.xpixel + this.widthpixel || y < this.ypixel || y > this.ypixel + this.heightpixel)) {
            this.mouseOutHandler(x, y);
            this.hovering = false;
        }
        this.mouseMoveHandler(x, y);
        return true;
    }
    checkMouseUp(x, y) {
        this.mouseUpHandler(x, y);
        return true;
    }
    mouseUpHandler(x, y) {
        // override this function in child classes to handle mouse up events
    }
    clickHandler(x, y) {
        // override this function in child classes to handle click events
    }
    mouseInHandler(x, y) {
        // override this function in child classes to handle hover events
    }
    mouseOutHandler(x, y) {
        // override this function in child classes to handle hover out events
    }
    mouseDownHandler(x, y) {
        // override this function in child classes to handle mouse down events
    }
    mouseMoveHandler(x, y) {
        // override this function in child classes to handle mouse move events
    }
    handleEvent(event, callback) {
        // either override this function in child classes or give a custom callback function to handle events
        if(callback) {
            callback(event);
        }
    }
}