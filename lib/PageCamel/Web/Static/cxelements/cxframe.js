class CXFrame extends CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._frame_color = "black";
        this._radius = 0;
        this._border_width = 1;
    }
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
    _drawFrame() {
        this._ctx.strokeStyle = this._frame_color;
        this._ctx.lineWidth = this._border_width;
        if (this._radius > 0) {
            this._drawRadius();
        }
        else {
            if (this._border_width > 0) {
                this._ctx.strokeRect(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2), this.widthpixel - Math.floor(this._border_width / 2), this.heightpixel - Math.floor(this._border_width / 2));
            }
        }
    }

    _draw() {
        this._drawFrame();
    }
    /**
     * @param {string} color - Color of the frame
     */
    set frame_color(color) {
        this._frame_color = color;
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
}