export class CXDefault {
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
        this._has_changed = false;
        this._takes_keyboard_input = false;
        this._active = true;
        this._px = 0;
        this._py = 0;
        this._pwidth = 0;
        this._pheight = 0;
        this._name = 'CXDefault';
    }
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
    _convertToPixel() {
    }
    _eventToXY(event) {
        var x = event.offsetX;
        var y = event.offsetY;
        return [x, y];
    }
    _clear() {
        if (this._redraw) {
            this._ctx.clearRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
            this._ctx.fillStyle = "#b3b3b3ff";
            this._ctx.fillRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        }
    }
    _tryRedraw(px = 0, py = 0, pwidth = this._ctx.canvas.width, pheight = this._ctx.canvas.height) {
        if (this._redraw && this._has_changed) {
            this.draw(px, py, pwidth, pheight);
        }
    }
    _draw() {
    }
    _calcRelXToPixel(rel_x = 0, max_width = this._ctx.canvas.width) {
        var x = rel_x;
        if (this._is_relative) {
            if (!isNaN(rel_x)) {
                x = rel_x * max_width;
            }
        }
        return x;
    }
    _calcRelYToPixel(rel_y = 0, max_height = this._ctx.canvas.height) {
        var y = rel_y;
        if (this._is_relative) {
            if (!isNaN(rel_y)) {
                y = rel_y * max_height;
            }
        }
        return y;
    }
    _calcRelativePositions(px, py, pwidth, pheight) {
        var xpixel = Math.floor(px + this._calcRelXToPixel(this._xpos, pwidth));
        var ypixel = Math.floor(py + this._calcRelYToPixel(this._ypos, pheight));
        var widthpixel = Math.ceil(this._calcRelXToPixel(this._width, pwidth));
        var heightpixel = Math.ceil(this._calcRelYToPixel(this._height, pheight));
        return [xpixel, ypixel, widthpixel, heightpixel];
    }
    _getViewInfo() {
    }
    _getMinSize() {
    }
    _getMaxSize() {
    }
    _checkEvent(event) {
        if (this._active) {
            switch (event.type) {
                case 'click':
                    var [mouse_x, mouse_y] = this._eventToXY(event);
                    return this._checkClick(mouse_x, mouse_y);
                case 'mousemove':
                    var [mouse_x, mouse_y] = this._eventToXY(event);
                    return this._checkMouseMove(mouse_x, mouse_y);
                case 'mousedown':
                    var [mouse_x, mouse_y] = this._eventToXY(event);
                    return this._checkMouseDown(mouse_x, mouse_y);
                case 'mouseup':
                    var [mouse_x, mouse_y] = this._eventToXY(event);
                    return this._checkMouseUp(mouse_x, mouse_y);
                case 'mouseleave':
                    var [mouse_x, mouse_y] = this._eventToXY(event);
                    return this._checkMouseLeave(mouse_x, mouse_y);
                case 'keydown':
                    return this._checkKeyDown();
                case 'keyup':
                    return this._checkKeyUp();
            }
        }
        return false;
    }
    checkEvent(event) {
        return this._checkEvent(event);
    }
    _checkClick(x, y) {
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            return true;
        }
        return false;
    }
    _checkMouseDown(x, y) {
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            this._mouse_down = true;
            return true;
        }
        this._mouse_down = false;
        return false;
    }
    _checkMouseMove(x, y) {
        if (this._mouse_down) {
            return true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this._mouse_over = true;
            return true;
        }
        else if (this._mouse_over) {
            this._mouse_over = false;
            return true;
        }
        return false;
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
        return true;
    }
    _checkKeyDown() {
        if (this._takes_keyboard_input) {
            return true;
        }
        return false;
    }
    _checkKeyUp() {
        if (this._takes_keyboard_input) {
            return true;
        }
        return false;
    }
    _handleEvent(event) {
        return false;
    }
    handleEvent(event) {
        var handled = false;
        if (this._active) {
            handled = this._handleEvent(event);
        }
        return handled;
    }
    _checkOverflow(x, y, width, height) {
        if (this._is_relative) {
            if (x < 0 || x > 1 || y < 0 || y > 1) {
                console.warn("Position is outside drawing area");
            }
            if (x + width > 1 || y + height > 1) {
                console.warn("Position and size is outside drawing area");
            }
        }
        else {
            if (x < 0 || x > this._ctx.canvas.width || y < 0 || y > this._ctx.canvas.height) {
                console.warn("Position is outside drawing area");
            }
            if (x + width > this._ctx.canvas.width || y + height > this._ctx.canvas.height) {
                console.warn("Position and size is outside drawing area");
            }
        }
        return false;
    }
    set width(width) {
        this._width = width;
    }
    get width() {
        return this._width;
    }
    set height(height) {
        this._height = height;
    }
    get height() {
        return this._height;
    }
    set xpos(x) {
        this._xpos = x;
    }
    get xpos() {
        return this._xpos;
    }
    set ypos(y) {
        this._ypos = y;
    }
    get ypos() {
        return this._ypos;
    }
    set is_relative(state) {
        this._is_relative = state;
    }
    get is_relative() {
        return this._is_relative;
    }
    set ctx(value) {
        this._ctx = value;
    }
    get ctx() {
        return this._ctx;
    }
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
    set active(state) {
        this._tryRedraw();
        this._active = state;
    }
    get active() {
        this._tryRedraw();
        return this._active;
    }
    set name(name) {
        this._name = name;
    }
    get name() {
        return this._name;
    }
    set attributes(attributes) {
        console.log(attributes);
        var valid_attributes = {};
        var keys = Object.keys(attributes);
        console.log(CXDefault.prototype);
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            var descriptor = Object.getOwnPropertyDescriptor(CXDefault.prototype, key);
            console.log(descriptor, key);
        }
        Object.assign(this, valid_attributes);
    }
    get attributes() {
        var attributes = {};
        var keys = Object.keys(this);
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            if (!key.startsWith("_")) {
                attributes[key] = this[key];
            }
        }
        return attributes;
    }
}
