class CXDragAndDrop extends CXButton {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._dragable = true;
        this._resizeable = true;
        this._show_resize_frame = false;
        this._box_size = 20;
        this._box_size_half = this._box_size / 2;
        this._mouse_down_x = 0;
        this._mouse_down_y = 0;
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
            this._ctx.stroke();
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
            this._ctx.stroke();
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
            this._ctx.stroke();
            this._ctx.fill();
            this._ctx.closePath();

            //draw draganddrop frame:
            this._ctx.strokeRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);


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
            this._show_resize_frame = true;
            this._has_changed = true;
            this._mouse_down_x = x;
            this._mouse_down_y = y;
        }
    }
    // if mouse is up hide the frame:
    _mouseUpHandler() {
        this._show_resize_frame = false;
        this._has_changed = true;
    }
    //mouse move handler:
    _mouseMoveHandler = ()  => {
        console.log('_mouseMoveHandler', 'is_mouse_down', this._mouse_down, 'show_resize_frame', this._show_resize_frame, ' is dragable', this._dragable);
        if (this._mouse_down && this._show_resize_frame && this._dragable) {
            var dx = this._mouse_down_x - this._mouse_x;
            var dy = this._mouse_down_y - this._mouse_y;
            this._xpixel -= dx;
            this._ypixel -= dy;
            this._widthpixel += dx;
            this._heightpixel += dy;
            this._mouse_down_x = this._mouse_x;
            this._mouse_down_y = this._mouse_y;
            this._has_changed = true;
        }
    }
    handleEvent(event) {
        super.handleEvent(event);
        var [x, y] = this._eventToXY(event);
        //convert mouse position to relative
        var xrel = this._calcRelXToPixel(this._px, this._pwidth);
        var yrel = this._calcRelYToPixel(this._py, this._pheight);
        
        //console.log('checking event: ' + event.type + ' at: ' + x + ',' + y, 'and _dragable: ' + this._dragable + ' and inside: ' + this._isInside(x, y));
        if (this._dragable) {
            if (event.type == "mousedown" && this._isInside(x, y)) {
                this._mouseDownHandler(xrel, yrel);
            }
            else if (event.type == "mouseup" && !this._isInside(x, y)) {
                this._mouseUpHandler();
            }
            else if (event.type == "mousemove") {
                this._mouseMoveHandler();
            }
        }
        this._tryRedraw();
    }
}