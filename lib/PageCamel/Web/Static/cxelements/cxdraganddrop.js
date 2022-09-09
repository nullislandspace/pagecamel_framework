import { CXButton } from "./cxbutton.js";
export class CXDragAndDrop extends CXButton {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super._border_width = 5;
        /** @protected */
        this._dragable = true;
        /** @protected */
        this._resizeable = true;
        /** @protected */
        this._show_resize_frame = false;
        /** @protected */
        this._box_size = 20; //size of the boxes that are used to resize the dragndrop
        /** @protected */
        this._box_size_half = this._box_size / 2; //half of the size of the boxes that are used to resize the dragndrop
        /** @protected */
        this._mouse_down_x = 0;
        /** @protected */
        this._mouse_down_y = 0;
        /** @protected */
        this._move_dragndrop = false;
        /** @protected */
        this._angle = 0; //angle of rotation in radians
        /** @protected */
        this._resize_mode = 'none'; //resize direction: n-resize, s-resize, e-resize, w-resize, ne-resize, se-resize, sw-resize, nw-resize
        /** @protected */
        this._rotate = false; //rotate the dragndrop
        /** @protected */
        this._center_x = 0; //center of the dragndrop
        /** @protected */
        this._center_y = 0; //center of the dragndrop

    }
    /**
     * @default this._xpos
     * @param {number} x - x coordinate of the dragndrop 
     * @default this._ypos
     * @param {number} y - y coordinates of the dragndrop
     * @description get the x and y coordinates of each corner of the dragndrop
     * @returns {number} [x1, y1, x2, y2, x3, y3, x4, y4]
     * @private
     */
    _calculateCornerPoints(x = this._xpos, y = this._ypos) {
        //calculate the corner points of the dragndrop at the current angle 
        var center_x = (x + this._width / 2) * this._pwidth + this._px;
        var center_y = (y + this._height / 2) * this._pheight + this._py;
        var [x1, y1] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth, this._py + y * this._pheight, this._angle);
        var [x2, y2] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth + this._width * this._pwidth, this._py + y * this._pheight, this._angle);
        var [x3, y3] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth + this._width * this._pwidth, this._py + y * this._pheight + this._height * this._pheight, this._angle);
        var [x4, y4] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth, this._py + y * this._pheight + this._height * this._pheight, this._angle);
        return [x1, y1, x2, y2, x3, y3, x4, y4];
    }

    /**
     * @description get the bounds of the dragndrop at the current angle
     * @returns {number} [min_x, min_y, max_x, max_y]
     * @private
     */
    _getRotatedBounds(x = this._xpos, y = this._ypos) {
        var [x1, y1, x2, y2, x3, y3, x4, y4] = this._calculateCornerPoints(x, y);
        var min_x = Math.min(x1, x2, x3, x4);
        var min_y = Math.min(y1, y2, y3, y4);
        var max_x = Math.max(x1, x2, x3, x4);
        var max_y = Math.max(y1, y2, y3, y4);
        return [min_x, min_y, max_x, max_y];
    }
    /**
     * @description remove the dragndrop from the canvas
     * @private
     */
    _clear() {
        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();
        //clear the area:
        ctx.clearRect(min_x - this._box_size * 2, min_y - this._box_size * 2, max_x - min_x + this._box_size * 4, max_y - min_y + this._box_size * 4);
        this._ctx.fillStyle = "#b3b3b3ff";
        this._ctx.fillRect(min_x - this._box_size * 2, min_y - this._box_size * 2, max_x - min_x + this._box_size * 4, max_y - min_y + this._box_size * 4);
    }
    /**
     * @description draws the frame for resizing
     * @private
     */
    _drawResizeFrame() {
        if (this._show_resize_frame && this._resizeable) {

            this._ctx.fillStyle = "black";
            this._ctx.strokeStyle = "black";
            this._ctx.lineWidth = 1;

            //draw resize corners:
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
            this._ctx.moveTo(this._xpixel + this._widthpixel / 2, this._ypixel);
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
            this._ctx.strokeStyle = "blue";
            this._ctx.fillStyle = "blue";
            this._ctx.beginPath();
            this._ctx.arc(this._center_x, this._center_y, 2, 0, 2 * Math.PI);
            this._ctx.stroke();
            this._ctx.fill();
            this._ctx.closePath();
        }
    }
    /**
     * @description draws the dragndrop
     * @protected
     */
    _draw() {
        ctx.save(); //saves the state of canvas
        ctx.translate(this._center_x, this._center_y); //translates the canvas to the center of the dragndrop
        ctx.rotate(this._angle); //rotates the canvas
        ctx.translate(-this._center_x, -this._center_y); //restores the canvas to the original position
        super._draw();
        this._drawResizeFrame();
        ctx.restore(); //restore the state of canvas
    }
    /**
     * @description handles the mouse down event
     * @protected
     */
    _mouseDownHandler = (x, y) => {
        if (this._resizeable) {
            this._has_changed = true;
            this._show_resize_frame = true;
            this._mouse_down_x = x;
            this._mouse_down_y = y;
            this._mouse_down_corner_distance_x = x - this._xpixel;
            this._mouse_down_corner_distance_y = y - this._ypixel;
            this._move_dragndrop = true;
        }
    }
    /**
     * @description handles the mouse up event
     * @protected
     */
    _mouseUpHandler = () => {
        this._move_dragndrop = false;
        this._resize_mode = 'none';
        this._has_changed = true;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
    }
    /**
     * @description removes the resize frame
     * @protected
     */
    _removeFrame = () => {
        this._show_resize_frame = false;
        this._has_changed = true;
    }
    /**
     * @description handles the rotation of the dragndrop
     * @protected
     * @param {number} x - the x coordinate of the mouse
     * @param {number} y - the y coordinate of the mouse
     */
    _rotatedragndrop = (x, y) => {
        this._createSaveValues();

        //rotate the dragndrop to the angle of the mouse:
        this._center_x = this._xpixel + this._widthpixel / 2;
        this._center_y = this._ypixel + this._heightpixel / 2;
        var dx = x - this._center_x; //mouse distance from center x
        var dy = y - this._center_y; //mouse distance from center y
        this._angle = Math.atan2(dy, dx) + Math.PI / 2; //angle between mouse and center

        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();

        //check if any of the corners is outside
        if (min_x < this._px || min_y < this._py || max_x > this._px + this._pwidth || max_y > this._py + this._pheight) {
            this._loadSaveValues();
        }
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
    }
    /**
     * @description creates temporary values for saving the current state of the dragndrop
     * @protected
     */
    _createSaveValues = () => {
        this._save_values = {
            xpos: this._xpos,
            ypos: this._ypos,
            width: this._width,
            height: this._height,
            angle: this._angle,
            center_x: this._center_x,
            center_y: this._center_y,
            angle: this._angle,
        }
    }
    /**
     * @description loads the saved values
     * @protected
     */
    _loadSaveValues = () => {
        this._xpos = this._save_values.xpos;
        this._ypos = this._save_values.ypos;
        this._width = this._save_values.width;
        this._height = this._save_values.height;
        this._angle = this._save_values.angle;
        this._center_x = this._save_values.center_x;
        this._center_y = this._save_values.center_y;
    }
    /**
     * @description handles the resize of the dragndrop
     * @protected
     * @param {number} x - the x coordinate of the mouse
     * @param {number} y - the y coordinate of the mouse
     */
    _resize = (x, y) => {
        this._has_changed = true;
        if (this._resize_mode == 'crosshair') {
            this._rotatedragndrop(x, y);
            return;
        }
        this._createSaveValues();

        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);

        //sets the default values
        var new_x = this._xpos * this._pwidth;
        var new_width = this._width * this._pwidth;
        var new_y = this._ypos * this._pheight;
        var new_height = this._height * this._pheight;
        if (this._resize_mode == 's-resize' || this._resize_mode == 'se-resize' || this._resize_mode == 'sw-resize') {
            //handles down resize
            new_height = rotated_y - this._ypos * this._pheight - this._py;
            if (new_height <= this._box_size + 5) {
                //limit the min height to the box size + 5
                new_height = this._box_size + 5;
            }
        }
        if (this._resize_mode == 'e-resize' || this._resize_mode == 'ne-resize' || this._resize_mode == 'se-resize') {
            //handles right resize
            new_width = rotated_x - this._xpos * this._pwidth - this._px;
            if (new_width <= this._box_size + 5) {
                //limit the min width to the box size + 5
                new_width = this._box_size + 5;
            }
        }
        if (this._resize_mode == 'n-resize' || this._resize_mode == 'ne-resize' || this._resize_mode == 'nw-resize') {
            //handles up resize
            new_y = rotated_y - this._py;
            new_height = this._height * this._pheight + (this._ypos * this._pheight) - rotated_y + this._py;
            if (new_height <= this._box_size + 5) {
                //limit the min height to the box size + 5
                new_y = new_y - (this._box_size + 5 - new_height);
                new_height = this._box_size + 5;
            }
        }
        if (this._resize_mode == 'w-resize' || this._resize_mode == 'nw-resize' || this._resize_mode == 'sw-resize') {
            // handles left resize
            new_x = rotated_x - this._px;
            new_width = this._width * this._pwidth + (this._xpos * this._pwidth) - rotated_x + this._px;
            if (new_width <= this._box_size + 5) {
                //limit the min width to the box size + 5
                new_x = new_x - (this._box_size + 5 - new_width);
                new_width = this._box_size + 5;
            }
        }

        //setting new values and converting it back to relative values
        this._xpos = new_x / this._pwidth;
        this._height = new_height / this._pheight;
        this._ypos = new_y / this._pheight;
        this._width = new_width / this._pwidth;

        // calculates the new center point of the dragndrop by rotating the center point to the new center point
        [this._center_x, this._center_y] = this._rotatePoint(this._center_x, this._center_y, new_x + new_width / 2 + this._px, new_y + new_height / 2 + this._py, -this._angle);


        // gets new _xpos and _ypos from the new center point
        this._xpos = (this._center_x - new_width / 2 - this._px) / this._pwidth;
        this._ypos = (this._center_y - new_height / 2 - this._py) / this._pheight;

        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();

        if (min_x < this._px || min_y < this._py || max_x > this._px + this._pwidth || max_y > this._py + this._pheight) {
            //if any of the corners is outside the box, reset the values
            this._loadSaveValues();
        }
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
    }
    /**
     * @description rotates a point around a given center point
     * @returns {number} [x,y] - the rotated point
     * @param {number} cx - the x coordinate of the center point
     * @param {number} cy - the y coordinate of the center point
     * @param {number} x - the x coordinate of the point to rotate
     * @param {number} y - the y coordinate of the point to rotate
     * @param {number} radians - the angle to rotate the point
     * @protected
     */
    _rotatePoint(cx, cy, x, y, radians) {
        //calculate the new x and y coordinates after rotation
        var cos = Math.cos(radians);
        var sin = Math.sin(radians);
        var nx = (cos * (x - cx)) + (sin * (y - cy)) + cx;
        var ny = (cos * (y - cy)) - (sin * (x - cx)) + cy;
        return [nx, ny];
    }
    /**
     * @description handles the movement of the dragndrop
     * @params {number} x - the x coordinate of the mouse
     * @params {number} y - the y coordinate of the mouse
     * @protected
     */
    _move = (x, y) => {
        this._has_changed = true;
        this._clear();
        var dx = x - this._mouse_down_x;
        var dy = y - this._mouse_down_y;
        var new_top_left_x = dx + this._mouse_down_x - this._mouse_down_corner_distance_x - this._px;
        var new_top_left_y = dy + this._mouse_down_y - this._mouse_down_corner_distance_y - this._py;

        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds(new_top_left_x / this._pwidth, new_top_left_y / this._pheight);

        // calculate the center by using the corner points
        this._center_x = min_x + (max_x - min_x) / 2;
        this._center_y = min_y + (max_y - min_y) / 2;

        if (min_x < this._px) {
            // prevent rotated dragndrop from going out of bounds on the left
            var offset = this._center_x - min_x - this._width * this._pwidth / 2;
            new_top_left_x = offset;
        }
        if (max_x > this._px + this._pwidth) {
            // prevent rotated dragndrop from going out of bounds on the right
            var offset = max_x - this._center_x - this._width * this._pwidth / 2 + this._px;
            new_top_left_x = this._px - offset + this._pwidth - this._width * this._pwidth;
        }
        if (min_y < this._py) {
            // prevent rotated dragndrop from going out of bounds on the top
            var offset = this._center_y - min_y - this._height * this._pheight / 2;
            new_top_left_y = offset;
        }
        if (max_y > this._py + this._pheight) {
            // prevent rotated dragndrop from going out of bounds on the bottom
            var offset = max_y - this._center_y - this._height * this._pheight / 2 + this._py;
            new_top_left_y = this._py - offset + this._pheight - this._height * this._pheight;
        }

        // calculate the new x and y positions
        this._xpos = new_top_left_x / this._pwidth;
        this._ypos = new_top_left_y / this._pheight;
        // calculate the new center distance
        this._center_x = this._xpos * this._pwidth + this._pwidth * this._width / 2 + this._px;
        this._center_y = this._ypos * this._pheight + this._pheight * this._height / 2 + this._py;
    }
    /**
     * @description handles the mouse move event
     * @params {number} x - the x coordinate of the mouse
     * @params {number} y - the y coordinate of the mouse
     * @protected
     */
    _mouseMoveHandler = (x, y) => {
        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
        if (!this._mouse_down) {
            this._checkResizeMode(rotated_x, rotated_y);
        }
        if (this._mouse_down && this._show_resize_frame && this._dragable && this._resize_mode == "none" && this._move_dragndrop) {
            //move dragndrop around
            this._move(x, y);
        }
        if (this._isInside(rotated_x, rotated_y) && this._resize_mode == "none") {
            this._ctx.canvas.style.cursor = 'move';
        }
        else if (this._resize_mode == "none") {
            this._ctx.canvas.style.cursor = 'default';
        }
        else if (this._mouse_down) {
            this._resize(x, y);
        }
    }
    /**
     * @description checks the resize mode
     * @params {number} x - the x coordinate of the mouse
     * @params {number} y - the y coordinate of the mouse
     * @protected
     */
    _checkResizeMode(x, y) {
        // check if the mouse is over a resize box
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
                // set the cursor according to the resize mode
                this._ctx.canvas.style.cursor = this._resize_mode;
            }
        }
        return this._resize_mode;
    }
    /**
     * @description checks if the object is influenced by the event
     * @returns {boolean}
     * @params {event} event - the event
     * @public
     */
    checkEvent(event) {
        //save locations
        var x = this._xpixel;
        var y = this._ypixel;
        var width = this._widthpixel;
        var height = this._heightpixel;

        //increase the size of the region where it checks for the event
        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();
        this._xpixel = min_x - this._box_size_half * 5;
        this._ypixel = min_y - this._box_size_half * 5;
        this._widthpixel = max_x - this._xpixel + this._box_size_half * 10;
        this._heightpixel = max_y - this._ypixel + this._box_size_half * 10;

        var result = this._checkEvent(event);

        //restore locations
        this._xpixel = x;
        this._ypixel = y;
        this._widthpixel = width;
        this._heightpixel = height;
        return result;
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    handleEvent(event) {
        super.handleEvent(event);
        var [x, y] = this._eventToXY(event);
        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
        if (this._dragable) {
            if (event.type == "mousedown" && this._isInside(rotated_x, rotated_y)) {
                if (this._checkResizeMode(rotated_x, rotated_y) == 'none') {
                    this._mouseDownHandler(x, y);
                }
            }
            else if (event.type == "mousedown" && !this._isInside(rotated_x, rotated_y)) {
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