import { CXButton } from "./cxbutton.js";
export class CXDragAndDrop extends CXButton {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._onMouseUp = () => {
            this._move_dragndrop = false;
            this._resize_mode = 'none';
            this._has_changed = true;
            this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        };
        this._removeFrame = () => {
            this._show_resize_frame = false;
            this._has_changed = true;
        };
        this._rotatedragndrop = (x, y) => {
            this._createSaveValues();
            this._center_x = this._xpixel + this._widthpixel / 2;
            this._center_y = this._ypixel + this._heightpixel / 2;
            this._pixelCenterToRelativeCenter();
            var dx = x - this._center_x;
            var dy = y - this._center_y;
            this._angle = Math.atan2(dy, dx) + Math.PI / 2;
            var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();
            if (min_x < this._px || min_y < this._py || max_x > this._px + this._pwidth || max_y > this._py + this._pheight) {
                this._loadSaveValues();
            }
            this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        };
        this._createSaveValues = () => {
            this._save_values = {
                xpos: this._xpos,
                ypos: this._ypos,
                width: this._width,
                height: this._height,
                angle: this._angle,
                center_x: this._center_x,
                center_y: this._center_y,
            };
        };
        this._loadSaveValues = () => {
            this._xpos = this._save_values.xpos;
            this._ypos = this._save_values.ypos;
            this._width = this._save_values.width;
            this._height = this._save_values.height;
            this._angle = this._save_values.angle;
            this._center_x = this._save_values.center_x;
            this._center_y = this._save_values.center_y;
            this._pixelCenterToRelativeCenter();
        };
        this._resize = (x, y) => {
            this._has_changed = true;
            if (this._resize_mode == 'crosshair') {
                this._rotatedragndrop(x, y);
                return;
            }
            this._createSaveValues();
            var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
            var new_x = this._xpos * this._pwidth;
            var new_width = this._width * this._pwidth;
            var new_y = this._ypos * this._pheight;
            var new_height = this._height * this._pheight;
            if (this._resize_mode == 's-resize' || this._resize_mode == 'se-resize' || this._resize_mode == 'sw-resize') {
                new_height = rotated_y - this._ypos * this._pheight - this._py;
                if (new_height <= this._box_size + 5) {
                    new_height = this._box_size + 5;
                }
            }
            if (this._resize_mode == 'e-resize' || this._resize_mode == 'ne-resize' || this._resize_mode == 'se-resize') {
                new_width = rotated_x - this._xpos * this._pwidth - this._px;
                if (new_width <= this._box_size + 5) {
                    new_width = this._box_size + 5;
                }
            }
            if (this._resize_mode == 'n-resize' || this._resize_mode == 'ne-resize' || this._resize_mode == 'nw-resize') {
                new_y = rotated_y - this._py;
                new_height = this._height * this._pheight + (this._ypos * this._pheight) - rotated_y + this._py;
                if (new_height <= this._box_size + 5) {
                    new_y = new_y - (this._box_size + 5 - new_height);
                    new_height = this._box_size + 5;
                }
            }
            if (this._resize_mode == 'w-resize' || this._resize_mode == 'nw-resize' || this._resize_mode == 'sw-resize') {
                new_x = rotated_x - this._px;
                new_width = this._width * this._pwidth + (this._xpos * this._pwidth) - rotated_x + this._px;
                if (new_width <= this._box_size + 5) {
                    new_x = new_x - (this._box_size + 5 - new_width);
                    new_width = this._box_size + 5;
                }
            }
            this._xpos = new_x / this._pwidth;
            this._height = new_height / this._pheight;
            this._ypos = new_y / this._pheight;
            this._width = new_width / this._pwidth;
            [this._center_x, this._center_y] = this._rotatePoint(this._center_x, this._center_y, new_x + new_width / 2 + this._px, new_y + new_height / 2 + this._py, -this._angle);
            this._pixelCenterToRelativeCenter();
            this._xpos = (this._center_x - new_width / 2 - this._px) / this._pwidth;
            this._ypos = (this._center_y - new_height / 2 - this._py) / this._pheight;
            var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();
            if (min_x < this._px || min_y < this._py || max_x > this._px + this._pwidth || max_y > this._py + this._pheight) {
                this._loadSaveValues();
            }
            this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        };
        this._move = (x, y) => {
            this._has_changed = true;
            this._clear();
            var dx = x - this._mouse_down_x;
            var dy = y - this._mouse_down_y;
            var new_top_left_x = dx + this._mouse_down_x - this._mouse_down_corner_distance_x - this._px;
            var new_top_left_y = dy + this._mouse_down_y - this._mouse_down_corner_distance_y - this._py;
            var [min_x, min_y, max_x, max_y] = this._getRotatedBounds(new_top_left_x / this._pwidth, new_top_left_y / this._pheight);
            this._center_x = min_x + (max_x - min_x) / 2;
            this._center_y = min_y + (max_y - min_y) / 2;
            this._pixelCenterToRelativeCenter();
            if (min_x < this._px) {
                var offset = this._center_x - min_x - this._width * this._pwidth / 2;
                new_top_left_x = offset;
            }
            if (max_x > this._px + this._pwidth) {
                var offset = max_x - this._center_x - this._width * this._pwidth / 2 + this._px;
                new_top_left_x = this._px - offset + this._pwidth - this._width * this._pwidth;
            }
            if (min_y < this._py) {
                var offset = this._center_y - min_y - this._height * this._pheight / 2;
                new_top_left_y = offset;
            }
            if (max_y > this._py + this._pheight) {
                var offset = max_y - this._center_y - this._height * this._pheight / 2 + this._py;
                new_top_left_y = this._py - offset + this._pheight - this._height * this._pheight;
            }
            this._xpos = new_top_left_x / this._pwidth;
            this._ypos = new_top_left_y / this._pheight;
            this._center_x = this._xpos * this._pwidth + this._pwidth * this._width / 2 + this._px;
            this._center_y = this._ypos * this._pheight + this._pheight * this._height / 2 + this._py;
            this._pixelCenterToRelativeCenter();
        };
        this._mouseMoveHandler = (x, y) => {
            var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
            if (!this._mouse_down) {
                this._checkResizeMode(rotated_x, rotated_y);
            }
            if (this._mouse_down && this._show_resize_frame && this._dragable && this._resize_mode == "none" && this._move_dragndrop) {
                this._move(x, y);
            }
            if (this.isInside(rotated_x, rotated_y) && this._resize_mode == "none") {
                this._ctx.canvas.style.cursor = 'move';
            }
            else if (this._resize_mode == "none") {
                this._ctx.canvas.style.cursor = 'default';
            }
            else if (this._mouse_down) {
                this._resize(x, y);
            }
        };
        this._mouse_down_corner_distance_x = 0;
        this._mouse_down_corner_distance_y = 0;
        this._save_values = { xpos: 0, ypos: 0, width: 0, height: 0, angle: 0, center_x: 0, center_y: 0 };
        super._border_width = 0.1;
        this._dragable = true;
        this._resizeable = true;
        this._show_resize_frame = false;
        this._box_size = 20;
        this._box_size_half = this._box_size / 2;
        this._mouse_down_x = 0;
        this._mouse_down_y = 0;
        this._move_dragndrop = false;
        this._angle = 0;
        this._resize_mode = 'none';
        this._rotate = false;
        this._center_x = 0;
        this._center_y = 0;
        this._rel_center_x = 0;
        this._rel_center_y = 0;
        this._name = "DragAndDrop";
    }
    _calculateCornerPoints(x = this._xpos, y = this._ypos) {
        var center_x = (x + this._width / 2) * this._pwidth + this._px;
        var center_y = (y + this._height / 2) * this._pheight + this._py;
        var [x1, y1] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth, this._py + y * this._pheight, this._angle);
        var [x2, y2] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth + this._width * this._pwidth, this._py + y * this._pheight, this._angle);
        var [x3, y3] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth + this._width * this._pwidth, this._py + y * this._pheight + this._height * this._pheight, this._angle);
        var [x4, y4] = this._rotatePoint(center_x, center_y, this._px + x * this._pwidth, this._py + y * this._pheight + this._height * this._pheight, this._angle);
        return [x1, y1, x2, y2, x3, y3, x4, y4];
    }
    _getRotatedBounds(x = this._xpos, y = this._ypos) {
        var [x1, y1, x2, y2, x3, y3, x4, y4] = this._calculateCornerPoints(x, y);
        var min_x = Math.min(x1, x2, x3, x4);
        var min_y = Math.min(y1, y2, y3, y4);
        var max_x = Math.max(x1, x2, x3, x4);
        var max_y = Math.max(y1, y2, y3, y4);
        return [min_x, min_y, max_x, max_y];
    }
    _clear() {
        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();
        this._ctx.clearRect(min_x - this._box_size * 2, min_y - this._box_size * 2, max_x - min_x + this._box_size * 4, max_y - min_y + this._box_size * 4);
        this._ctx.fillStyle = "#b3b3b3ff";
        this._ctx.fillRect(min_x - this._box_size * 2, min_y - this._box_size * 2, max_x - min_x + this._box_size * 4, max_y - min_y + this._box_size * 4);
    }
    _drawResizeFrame() {
        if (this._show_resize_frame && this._resizeable) {
            this._ctx.fillStyle = "black";
            this._ctx.strokeStyle = "black";
            this._ctx.lineWidth = 1;
            this._ctx.beginPath();
            this._ctx.rect(this._xpixel - this._box_size_half, this._ypixel - this._box_size_half, this._box_size, this._box_size);
            this._ctx.rect(this._xpixel + this._widthpixel - this._box_size_half, this._ypixel - this._box_size_half, this._box_size, this._box_size);
            this._ctx.rect(this._xpixel + this._widthpixel - this._box_size_half, this._ypixel + this._heightpixel - this._box_size_half, this._box_size, this._box_size);
            this._ctx.rect(this._xpixel - this._box_size_half, this._ypixel + this._heightpixel - this._box_size_half, this._box_size, this._box_size);
            this._ctx.fill();
            this._ctx.closePath();
            this._ctx.beginPath();
            if (this._widthpixel > this._box_size * 2) {
                this._ctx.rect(this._xpixel + this._widthpixel / 2 - this._box_size_half, this._ypixel - this._box_size_half, this._box_size, this._box_size);
                this._ctx.rect(this._xpixel + this._widthpixel / 2 - this._box_size_half, this._ypixel + this._heightpixel - this._box_size_half, this._box_size, this._box_size);
            }
            if (this._heightpixel > this._box_size * 2) {
                this._ctx.rect(this._xpixel - this._box_size_half, this._ypixel + this._heightpixel / 2 - this._box_size_half, this._box_size, this._box_size);
                this._ctx.rect(this._xpixel + this._widthpixel - this._box_size_half, this._ypixel + this._heightpixel / 2 - this._box_size_half, this._box_size, this._box_size);
            }
            this._ctx.fill();
            this._ctx.closePath();
            this._ctx.beginPath();
            this._ctx.moveTo(this._xpixel + this._widthpixel / 2, this._ypixel);
            this._ctx.lineTo(this._xpixel + this._widthpixel / 2, this._ypixel - this._box_size_half - this._box_size);
            this._ctx.stroke();
            this._ctx.closePath();
            this._ctx.beginPath();
            this._ctx.arc(this._xpixel + this._widthpixel / 2, this._ypixel - this._box_size_half - this._box_size, this._box_size_half, 0, 2 * Math.PI);
            this._ctx.fill();
            this._ctx.closePath();
            this._ctx.strokeRect(this._xpixel + this._ctx.lineWidth / 2, this._ypixel + this._ctx.lineWidth / 2, this._widthpixel - this._ctx.lineWidth, this._heightpixel - this._ctx.lineWidth);
        }
    }
    _draw() {
        this._center_x = this._rel_center_x * this._pwidth + this._px;
        this._center_y = this._rel_center_y * this._pheight + this._py;
        this._ctx.save();
        this._ctx.translate(this._center_x, this._center_y);
        this._ctx.rotate(this._angle);
        this._ctx.translate(-this._center_x, -this._center_y);
        super._draw();
        this._drawResizeFrame();
        this._ctx.restore();
    }
    _onMouseDown(x, y) {
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
    _pixelCenterToRelativeCenter() {
        this._rel_center_x = (this._center_x - this._px) / this._pwidth;
        this._rel_center_y = (this._center_y - this._py) / this._pheight;
    }
    _rotatePoint(cx, cy, x, y, radians) {
        var cos = Math.cos(radians);
        var sin = Math.sin(radians);
        var nx = (cos * (x - cx)) + (sin * (y - cy)) + cx;
        var ny = (cos * (y - cy)) - (sin * (x - cx)) + cy;
        return [nx, ny];
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
                this._resize_mode = 'crosshair';
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
    checkEvent(event) {
        var x = this._xpixel;
        var y = this._ypixel;
        var width = this._widthpixel;
        var height = this._heightpixel;
        var [min_x, min_y, max_x, max_y] = this._getRotatedBounds();
        this._xpixel = min_x - this._box_size_half * 5;
        this._ypixel = min_y - this._box_size_half * 5;
        this._widthpixel = max_x - this._xpixel + this._box_size_half * 10;
        this._heightpixel = max_y - this._ypixel + this._box_size_half * 10;
        var result = this._checkEvent(event);
        this._xpixel = x;
        this._ypixel = y;
        this._widthpixel = width;
        this._heightpixel = height;
        return result;
    }
    _handleEvent(event) {
        super._handleEvent(event);
        var [x, y] = this._eventToXY(event);
        var [rotated_x, rotated_y] = this._rotatePoint(this._center_x, this._center_y, x, y, this._angle);
        if (this._dragable) {
            if (event.type == "mousedown" && this.isInside(rotated_x, rotated_y)) {
                if (this._checkResizeMode(rotated_x, rotated_y) == 'none') {
                    this._onMouseDown(x, y);
                }
            }
            else if (event.type == "mousedown" && !this.isInside(rotated_x, rotated_y)) {
                this._move_dragndrop = false;
            }
            else if (event.type == "mouseup") {
                this._onMouseUp();
            }
            else if (event.type == "mousemove") {
                this._mouseMoveHandler(x, y);
            }
        }
        return this._has_changed;
    }
}
