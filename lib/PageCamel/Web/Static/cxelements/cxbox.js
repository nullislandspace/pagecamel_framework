class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._box_color = "green";
    }
    _drawBox() {
        ctx.fillStyle = this._box_color;
        super._draw();
        if (this._radius > 0) {
            //fill rounded rectangle
            ctx.fill();
        }
        else {
            //fill rectangle
            ctx.fillRect(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2), this.widthpixel - Math.floor(this._border_width / 2), this.heightpixel - Math.floor(this._border_width / 2));
        }
    }
    _draw() {
        this._drawBox();
    }
    /**
     * @param {string} color - Color of the box
     */
    set box_color(color) {
        this._box_color = color;
    }
    get box_color() {
        return this._box_color;
    }
}