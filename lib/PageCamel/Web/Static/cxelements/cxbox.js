class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.box_color = "green";
    }
    _drawBox() {
        ctx.fillStyle = this.box_color;
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
}