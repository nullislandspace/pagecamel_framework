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
        this._ctx.moveTo(this.xpixel + this.radius + Math.ceil(this.border_width / 2), this.ypixel + Math.ceil(this.border_width / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - this.radius - Math.ceil(this.border_width / 2), this.ypixel + Math.ceil(this.border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this.border_width / 2), this.ypixel + Math.ceil(this.border_width / 2), this.xpixel + this.widthpixel - Math.ceil(this.border_width / 2), this.ypixel + this.radius + Math.ceil(this.border_width / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - Math.ceil(this.border_width / 2), this.ypixel + this.heightpixel - this.radius - Math.ceil(this.border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this.border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this.border_width / 2), this.xpixel + this.widthpixel - this.radius - Math.ceil(this.border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this.border_width / 2));
        this._ctx.lineTo(this.xpixel + this.radius + Math.ceil(this.border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this.border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this.border_width / 2), this.ypixel + this.heightpixel - Math.ceil(this.border_width / 2), this.xpixel + Math.ceil(this.border_width / 2), this.ypixel + this.heightpixel - this.radius - Math.ceil(this.border_width / 2));
        this._ctx.lineTo(this.xpixel + Math.ceil(this.border_width / 2), this.ypixel + this.radius + Math.ceil(this.border_width / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this.border_width / 2), this.ypixel + Math.ceil(this.border_width / 2), this.xpixel + this.radius + Math.ceil(this.border_width / 2), this.ypixel + Math.ceil(this.border_width / 2));
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