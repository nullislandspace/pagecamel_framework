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
    }
    _clear() {
        this._ctx.clearRect(this._xpixel - this._box_size_half, this._ypixel - this._box_size * 2, this._widthpixel + this._box_size, this._heightpixel + this._box_size_half * 5);
        this._ctx.fillStyle = "#b3b3b3ff";
        this._ctx.fillRect(this._xpixel - this._box_size_half, this._ypixel - this._box_size * 2, this._widthpixel + this._box_size, this._heightpixel + this._box_size_half * 5);
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
            this._ctx.arc(this._xpixel + this._widthpixel / 2, this._ypixel + this._heightpixel / 2, 2, 0, 2 * Math.PI);
            this._ctx.stroke();
            this._ctx.fill();
        }
    }
    //draw the frame:
    _draw() {
        super._draw();
        this._drawResizeFrame();
    }
    // if mouse is down show the frame:
    _mouseDownHandler = (x, y) => {
        if (this._resizeable) {
            console.log('Mouse is down now', x, y);
            this._show_resize_frame = true;
            this._mouse_down_x = x;
            this._mouse_down_y = y;
            this._mouse_down_corner_distance_x = x - this._xpixel;
            this._mouse_down_corner_distance_y = y - this._ypixel;
        }
    }
    // if mouse is up hide the frame:
    _mouseUpHandler() {
        this._show_resize_frame = false;
        this._has_changed = true;
    }
    //mouse move handler:
    _mouseMoveHandler = (x, y) => {
        console.log('_mouseMoveHandler', 'is_mouse_down', this._mouse_down, 'show_resize_frame', this._show_resize_frame, ' is dragable', this._dragable);
        if (this._mouse_down && this._show_resize_frame && this._dragable) {
            this._has_changed = true;
            this._clear();
            var dx = x - this._mouse_down_x;
            var dy = y - this._mouse_down_y;
            var new_x = (this._xpos + dx + this._mouse_down_x - this._mouse_down_corner_distance_x) / this._pwidth;
            var new_y = (this._ypos + dy + this._mouse_down_y - this._mouse_down_corner_distance_y) / this._pheight;
            this._xpos = new_x;
            this._ypos = new_y;
        }
    }
    handleEvent(event) {
        super.handleEvent(event);
        var [x, y] = this._eventToXY(event);
        //console.log('checking event: ' + event.type + ' at: ' + x + ',' + y, 'and _dragable: ' + this._dragable + ' and inside: ' + this._isInside(x, y));
        if (this._dragable) {
            if (event.type == "mousedown" && this._isInside(x, y)) {
                this._mouseDownHandler(x, y);
            }
            else if (event.type == "mouseup" && !this._isInside(x, y)) {
                this._mouseUpHandler();
            }
            else if (event.type == "mousemove") {
                this._mouseMoveHandler(x, y);
            }
        }
        this._tryRedraw();
    }

}