class CXFrame extends CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.frame_color = "black";
        this.radius = 0;
        this.border_width = 1;
    }
    _drawRadius() {
        // draw rounded rectangle
        this._ctx.beginPath();
        this._ctx.moveTo(this.xpixel + this.radius, this.ypixel);
        this._ctx.lineTo(this.xpixel + this.widthpixel - this.radius, this.ypixel);
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel, this.ypixel, this.xpixel + this.widthpixel, this.ypixel + this.radius);
        this._ctx.lineTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel - this.radius);
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel, this.xpixel + this.widthpixel - this.radius, this.ypixel + this.heightpixel);
        this._ctx.lineTo(this.xpixel + this.radius, this.ypixel + this.heightpixel);
        this._ctx.quadraticCurveTo(this.xpixel, this.ypixel + this.heightpixel, this.xpixel, this.ypixel + this.heightpixel - this.radius);
        this._ctx.lineTo(this.xpixel, this.ypixel + this.radius);
        this._ctx.quadraticCurveTo(this.xpixel, this.ypixel, this.xpixel + this.radius, this.ypixel);
        this._ctx.stroke();
    }
    _drawFrame() {
        this._ctx.strokeStyle = this.frame_color;
        this._ctx.lineWidth = this.border_width;
        if (this.radius > 0) {
            this._drawRadius();
        }
        else {
            this._ctx.strokeRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
    }
    _draw() {
        this._drawFrame();
    }
}