class CXDragAndDrop extends CXButton {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super._border_width = 5;
        this._dragable = true;
        this._resizeable = true;
        this._show_resize_frame = false;
        this._box_size = 20;
        this._box_size_half = this._box_size / 2;
        this._mouse_down_x = 0;
        this._mouse_down_y = 0;
        this._move_dragndrop = false;
        this._angle = 0; //angle of rotation in radians
        this._resize_mode = 'none'; //resize direction: n-resize, s-resize, e-resize, w-resize, ne-resize, se-resize, sw-resize, nw-resize
        this._rotate = false; //rotate the dragndrop
        this._center_x = 0; //center of the dragndrop
        this._center_y = 0; //center of the dragndrop
    }
    _calculateCornerPoints() {
        //calculate the corner points of the dragndrop at the current angle 
        var [x1, y1] = this._rotatePoint(this._center_x, this._center_y, this._xpixel, this._ypixel, this._angle);
        var [x2, y2] = this._rotatePoint(this._center_x, this._center_y, this._xpixel + this._widthpixel, this._ypixel, this._angle);
        var [x3, y3] = this._rotatePoint(this._center_x, this._center_y, this._xpixel + this._widthpixel, this._ypixel + this._heightpixel, this._angle);
        var [x4, y4] = this._rotatePoint(this._center_x, this._center_y, this._xpixel, this._ypixel + this._heightpixel, this._angle);
        return [x1, y1, x2, y2, x3, y3, x4, y4];
    }
    _clear() {
        //has some issues with the rotation
        var [x1, y1, x2, y2, x3, y3, x4, y4] = this._calculateCornerPoints();
        //get the 2 smallest x and y values and the 2 largest x and y values:
        var x_min = Math.min(x1, x2, x3, x4);
        var y_min = Math.min(y1, y2, y3, y4);
        var x_max = Math.max(x1, x2, x3, x4);
        var y_max = Math.max(y1, y2, y3, y4);
        //console.log(x_min, y_min, x_max, y_max);
        //clear the area:
        ctx.clearRect(x_min - this._box_size * 2, y_min - this._box_size * 2, x_max - x_min + this._box_size * 4, y_max - y_min + this._box_size * 4);
        this._ctx.fillStyle = "#b3b3b3ff";
        this._ctx.fillRect(x_min - this._box_size * 2, y_min - this._box_size * 2, x_max - x_min + this._box_size * 4, y_max - y_min + this._box_size * 4);
    }
    checkEvent(event) {
        //save locations:
        var x = this._xpixel;
        var y = this._ypixel;
        var width = this._widthpixel;
        var height = this._heightpixel;

        //change locations:
        this._xpixel -= this._box_size_half;
        this._ypixel -= this._box_size * 2;
        this._widthpixel += this._box_size;
        this._heightpixel += this._box_size_half * 5;

        var result = this._checkEvent(event);

        //restore locations:
        this._xpixel = x;
        this._ypixel = y;
        this._widthpixel = width;
        this._heightpixel = height;
        return result;
    }

    _drawResizeFrame() {
        if (this._show_resize_frame && this._resizeable) {

            this._ctx.fillStyle = "black";
            this._ctx.strokeStyle = "black";
            this._ctx.lineWidth = 1;

            //draw corners:
            this._ctx.beginPath();
            this._ctx.rect(this._xpixel - this._box_size_half, this._ypixel - this._box_size_half, this._box_size, this._box_size); //top left
            this._ctx.rect(this._xpixel + this._widthpixel - this._box_size_half, this._ypixel - this._box_size_half, this._box_size, this._box_size); //top right
            this._ctx.rect(this._xpixel + this._widthpixel - this._box_size_half, this._ypixel + this._heightpixel - this._box_size_half, this._box_size, this._box_size); //bottom right
            this._ctx.rect(this._xpixel - this._box_size_half, this._ypixel + this._heightpixel - this._box_size_half, this._box_size, this._box_size); //bottom left
            this._ctx.fill();
            this._ctx.closePath();

            //draw edge resize boxes:
            this._ctx.beginPath();
            if (this._widthpixel > this._box_size * 2) {
                this._ctx.rect(this._xpixel + this._widthpixel / 2 - this._box_size_half, this._ypixel - this._box_size_half, this._box_size, this._box_size); //top
                this._ctx.rect(this._xpixel + this._widthpixel / 2 - this._box_size_half, this._ypixel + this._heightpixel - this._box_size_half, this._box_size, this._box_size); //bottom
            }
            if (this._heightpixel > this._box_size * 2) {
                this._ctx.rect(this._xpixel - this._box_size_half, this._ypixel + this._heightpixel / 2 - this._box_size_half, this._box_size, this._box_size); //left
                this._ctx.rect(this._xpixel + this._widthpixel - this._box_size_half, this._ypixel + this._heightpixel / 2 - this._box_size_half, this._box_size, this._box_size); //right
            }
            this._ctx.fill();
            this._ctx.closePath();

            //draw a line from the top center up 
            this._ctx.beginPath();
            this._ctx.moveTo(this._xpixel + this._widthpixel / 2, this._ypixel - this._box_size_half);
            this._ctx.lineTo(this._xpixel + this._widthpixel / 2, this._ypixel - this._box_size_half - this._box_size);
            this._ctx.stroke();
            this._ctx.closePath();

            //draw a circel above the line:
            this._ctx.beginPath();
            this._ctx.arc(this._xpixel + this._widthpixel / 2, this._ypixel - this._box_size_half - this._box_size, this._box_size_half, 0, 2 * Math.PI);
            this._ctx.fill();
            this._ctx.closePath();

            //draw draganddrop frame:
            this._ctx.strokeRect(this._xpixel + this._ctx.lineWidth / 2, this._ypixel + this._ctx.lineWidth / 2, this._widthpixel - this._ctx.lineWidth, this._heightpixel - this._ctx.lineWidth);


            //debug circle at the center with radius 2:            
            this._ctx.strokeStyle = "red";
            this._ctx.fillStyle = "red";
            this._ctx.beginPath();
            this._ctx.arc(this._center_x, this._center_y, 2, 0, 2 * Math.PI);
            this._ctx.stroke();
            this._ctx.fill();
        }
    }
    //draw the frame:
    _draw() {
        //this._center_x = this._xpixel + this._widthpixel / 2;
        //this._center_y = this._ypixel + this._heightpixel / 2;
        ctx.save(); //saves the state of canvas
        ctx.translate(this._center_x, this._center_y); //translates the canvas to the center of the dragndrop
        ctx.rotate(this._angle); //rotates the canvas
        ctx.translate(-this._center_x, -this._center_y); //translates the canvas to the center of the dragndrop 
        super._draw();
        this._drawResizeFrame();
        ctx.restore(); //restore the state of canvas
    }
    // if mouse is down show the frame:
    _mouseDownHandler = (x, y) => {
        //console.log("mouse down");
        if (this._resizeable) {
            //console.log('Mouse is down now', x, y);
            this._has_changed = true;
            this._show_resize_frame = true;
            this._mouse_down_x = x;
            this._mouse_down_y = y;
            this._mouse_down_corner_distance_x = x - this._xpixel;
            this._mouse_down_corner_distance_y = y - this._ypixel;
            this._move_dragndrop = true;
        }
    }
    // if mouse is up hide the frame:
    _mouseUpHandler = () => {
        console.log("Mouse uphandler triggered");
        var [x1, y1, x2, y2, x3, y3, x4, y4] = this._calculateCornerPoints();
        //this._center_x = this._xpixel + this._widthpixel / 2;
        //this._center_y = this._ypixel + this._heightpixel / 2;
        console.log('x1,y1', x1, y1, 'x2,y2', x2, y2, 'x3,y3', x3, y3, 'x4,y4', x4, y4);
        //this._center_x = (x1 + x2 + x3 + x4) / 4;
        //this._center_y = (y1 + y2 + y3 + y4) / 4;
        //this._xpos = (this._center_x - this._widthpixel / 2) / this._pwidth;
        //this._ypos = (this._center_y - this._heightpixel / 2) / this._pheight;
        //this._xpos = (x1 + x2 + x3 + x4) / 4 / this._pwidth;
        //this._ypos = (y1 + y2 + y3 + y4) / 4 / this._pheight;
        this._move_dragndrop = false;
        this._resize_mode = 'none';
        this._has_changed = true;
    }
    _removeFrame = () => {
        //console.log('remove frame');
        this._show_resize_frame = false;
        this._has_changed = true;
    }

    _rotatedragndrop = (x, y) => {
        this._center_x = this._xpixel + this._widthpixel / 2;
        this._center_y = this._ypixel + this._heightpixel / 2;
        var dx = x - this._center_x; //mouse distance from center x
        var dy = y - this._center_y; //mouse distance from center y
        this._angle = Math.atan2(dy, dx) + Math.PI / 2; //angle between mouse and center
    }
    _resize = (x, y) => {
        this._has_changed = true;
        this._clear();
        if (this._resize_mode == 'crosshair') {
            this._rotatedragndrop(x, y);
            return;
        }
        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
        var new_height = this._heightpixel;
        var new_width = this._widthpixel;
        var new_x = this._xpixel;
        var new_y = this._ypixel;
        if (this._resize_mode == 's-resize' || this._resize_mode == 'se-resize' || this._resize_mode == 'sw-resize') {
            new_height = rotated_y - this._ypixel;
            if (new_height <= this._box_size + 2) {
                new_height = this._box_size + 2;
            }
        }
        if (this._resize_mode == 'e-resize' || this._resize_mode == 'ne-resize' || this._resize_mode == 'se-resize') {
            new_width = rotated_x - this._xpixel;
            if (new_width <= this._box_size + 2) {
                new_width = this._box_size + 2;
            }
        }
        if (this._resize_mode == 'n-resize' || this._resize_mode == 'ne-resize' || this._resize_mode == 'nw-resize') {
            new_y = rotated_y;
            new_height = this._heightpixel + (this._ypixel - rotated_y);
            if (new_height <= this._box_size + 2) {
                new_y = new_y - (this._box_size + 2 - new_height);
                new_height = this._box_size + 2;
            }
        }
        if (this._resize_mode == 'w-resize' || this._resize_mode == 'nw-resize' || this._resize_mode == 'sw-resize') {
            new_x = rotated_x;
            new_width = this._widthpixel + (this._xpixel - rotated_x);
            if (new_width <= this._box_size + 2) {
                new_x = new_x - (this._box_size + 2 - new_width);
                new_width = this._box_size + 2;
            }
        }
        this._xpos = new_x / this._pwidth;
        this._ypos = new_y / this._pheight;
        this._width = new_width / this._pwidth;
        this._height = new_height / this._pheight;
        //console.log('previos center', this._center_x, this._center_y);
        [this._center_x, this._center_y] = this._rotatePoint(this._center_x, this._center_y, new_x + new_width / 2, new_y + new_height / 2, -this._angle);
        //console.log('new center', this._center_x, this._center_y);
        this._xpos = (this._center_x - this._widthpixel / 2) / this._pwidth;
        this._ypos = (this._center_y - this._heightpixel / 2) / this._pheight;
    }
    _rotatePoint(cx, cy, x, y, radians) {
        //calculate the new x and y coordinates after rotation
        var cos = Math.cos(radians);
        var sin = Math.sin(radians);
        var nx = (cos * (x - cx)) + (sin * (y - cy)) + cx;
        var ny = (cos * (y - cy)) - (sin * (x - cx)) + cy;
        return [nx, ny];
    }
    _move = (x, y) => {
        this._has_changed = true;
        this._clear();
        var dx = x - this._mouse_down_x;
        var dy = y - this._mouse_down_y;
        var new_x = (this._xpos + dx + this._mouse_down_x - this._mouse_down_corner_distance_x) / this._pwidth;
        var new_y = (this._ypos + dy + this._mouse_down_y - this._mouse_down_corner_distance_y) / this._pheight;
        this._xpos = new_x;
        this._ypos = new_y;
        //calculate new center
        this._center_x = this._xpixel + this._widthpixel / 2;
        this._center_y = this._ypixel + this._heightpixel / 2;
    }
    //mouse move handler:
    _mouseMoveHandler = (x, y) => {
        //console.log('_mouseMoveHandler', 'is_mouse_down', this._mouse_down, 'show_resize_frame', this._show_resize_frame, ' is dragable', this._dragable);
        //console.log('resizemode', this._resize_mode);
        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
        //console.log('rotated_x', rotated_x, 'rotated_y', rotated_y, 'x', x, 'y', y, 'center_x', this._center_x, 'center_y', this._center_y);
        if (!this._mouse_down) {
            this._checkResizeMode(rotated_x, rotated_y);
        }
        if (this._mouse_down && this._show_resize_frame && this._dragable && this._resize_mode == "none" && this._move_dragndrop) {
            //move dragndrop around
            this._move(x, y);
        }
        if (this._isInside(x, y) && this._resize_mode == "none") {
            this._ctx.canvas.style.cursor = 'move';
        }
        else if (this._resize_mode == "none") {
            this._ctx.canvas.style.cursor = 'default';
        }
        else if (this._mouse_down) {
            this._resize(x, y);
        }

    }
    _checkResizeMode(x, y) {
        if (this._show_resize_frame) {
            if (x > this._xpixel + this._widthpixel - this._box_size_half && x < this._xpixel + this._widthpixel + this._box_size_half && y > this._ypixel + this._heightpixel - this._box_size_half && y < this._ypixel + this._heightpixel + this._box_size_half) {
                this._resize_mode = 'se-resize';
            }
            else if (x > this._xpixel - this._box_size_half && x < this._xpixel + this._box_size_half && y > this._ypixel + this._heightpixel - this._box_size_half && y < this._ypixel + this._heightpixel + this._box_size_half) {
                this._resize_mode = 'sw-resize';
            }
            else if (x > this._xpixel + this._widthpixel - this._box_size_half && x < this._xpixel + this._widthpixel + this._box_size_half && y > this._ypixel - this._box_size_half && y < this._ypixel + this._box_size_half) {
                this._resize_mode = 'ne-resize';
            }
            else if (x > this._xpixel - this._box_size_half && x < this._xpixel + this._box_size_half && y > this._ypixel - this._box_size_half && y < this._ypixel + this._box_size_half) {
                this._resize_mode = 'nw-resize';
            }
            else if (x > this._xpixel + this._widthpixel - this._box_size_half && x < this._xpixel + this._widthpixel + this._box_size_half && y > this._ypixel + this._heightpixel / 2 - this._box_size_half && y < this._ypixel + this._heightpixel / 2 + this._box_size_half) {
                this._resize_mode = 'e-resize';
            }
            else if (x > this._xpixel - this._box_size_half && x < this._xpixel + this._box_size_half && y > this._ypixel + this._heightpixel / 2 - this._box_size_half && y < this._ypixel + this._heightpixel / 2 + this._box_size_half) {
                this._resize_mode = 'w-resize';
            }
            else if (x > this._xpixel + this._widthpixel / 2 - this._box_size_half && x < this._xpixel + this._widthpixel / 2 + this._box_size_half && y > this._ypixel + this._heightpixel - this._box_size_half && y < this._ypixel + this._heightpixel + this._box_size_half) {
                this._resize_mode = 's-resize';
            }
            else if (x > this._xpixel + this._widthpixel / 2 - this._box_size_half && x < this._xpixel + this._widthpixel / 2 + this._box_size_half && y > this._ypixel - this._box_size_half && y < this._ypixel + this._box_size_half) {
                this._resize_mode = 'n-resize';
            }
            else if (x > this._xpixel + this._widthpixel / 2 - this._box_size_half && x < this._xpixel + this._widthpixel / 2 + this._box_size_half && y > this._ypixel - this._box_size_half * 4 && y < this._ypixel - this._box_size_half * 2) {
                this._resize_mode = 'crosshair'; //rotate
            }
            else {
                this._resize_mode = 'none';
            }
            if (this._resize_mode != "none") {
                this._ctx.canvas.style.cursor = this._resize_mode;
            }
        }
        return this._resize_mode;
    }
    handleEvent(event) {
        super.handleEvent(event);
        var [x, y] = this._eventToXY(event);
        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
        //console.log('checking event: ' + event.type + ' at: ' + x + ',' + y, 'and _dragable: ' + this._dragable + ' and inside: ' + this._isInside(x, y));
        if (this._dragable) {
            if (event.type == "mousedown" && this._isInside(x, y)) {
                console.log('mousedown inside');
                if (this._checkResizeMode(rotated_x, rotated_y) == 'none') {
                    this._mouseDownHandler(rotated_x, rotated_y);
                }
            }
            else if (event.type == "mousedown" && !this._isInside(x, y)) {
                //console.log('mousedown outside');
                this._move_dragndrop = false;
            }
            else if (event.type == "mouseup") {
                this._mouseUpHandler();
            }
            else if (event.type == "mousemove") {
                this._mouseMoveHandler(x, y);
            }
        }
    }
}