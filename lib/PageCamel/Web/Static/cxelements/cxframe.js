//import { CXDefault } from "./cxdefault";
/*export*/ class CXFrame extends CXDefault {
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
        super(ctx, x, y, width, height, is_relative, redraw);
        /** @protected */
        this._border_color = "black";
        /** @protected */
        this._radius = 0;
        /** @protected */
        this._border_width = 1;
    }
    _isInside(x, y) {
        return (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel);
    }
    /**
     * @protected
     * @description draws the frame with a radius
     */
    _drawRadius() {
        // draw rounded rectangle
        this._ctx.beginPath();
        this._ctx.moveTo(this.xpixel + this._radius + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - this._radius - Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2), this.xpixel + this.widthpixel - Math.ceil(this._border_width / 2), this.ypixel + this._radius + Math.ceil(this._border_width / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width / 2), this.ypixel + this.heightpixel - this._radius - Math.ceil(this._border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width / 2), this.xpixel + this.widthpixel - this._radius - Math.ceil(this._border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width / 2));
        this._ctx.lineTo(this.xpixel + this._radius + Math.ceil(this._border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width / 2), this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + this.heightpixel - this._radius - Math.ceil(this._border_width / 2));
        this._ctx.lineTo(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + this._radius + Math.ceil(this._border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2), this.xpixel + this._radius + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2));
        if (this._border_width > 0) {
            this._ctx.stroke();
        }

    }
    /**
     * @protected
     */
    _drawFrame() {
        this._ctx.strokeStyle = this._border_color;
        this._ctx.lineWidth = this._border_width;
        if (this._radius > 0) {
            this._drawRadius();
        }
        else {
            if (this._border_width > 0) {
                this._ctx.strokeRect(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2), this.widthpixel - this._border_width, this.heightpixel - this._border_width);
            }
        }
    }

    _draw() {
        this._drawFrame();
    }
    /**
     * @param {string} color - Color of the frame
     */
    set border_color(color) {
        this._border_color = color;
    }
    get border_color() {
        return this._border_color;
    }
    /**
     * @param {number} r - Radius of the frame
     */
    set radius(r) {
        this._radius = r;
    }
    get radius() {
        return this._radius;
    }
    /**
     * @param {number} w - Width of the frame
     */
    set border_width(w) {
        this._border_width = w;
    }
    get border_width() {
        return this._border_width;
    }

}