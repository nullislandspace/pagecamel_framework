class CXFrame extends CXDefault {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.frame_color = "black";
        this.radius = 0;
        this.border_width = 1;
        this.hovering = false;
    }
    _drawRadius() {
        // draw rounded rectangle
        this.ctx.beginPath();
        this.ctx.moveTo(this.xpixel + this.radius, this.ypixel);
        this.ctx.lineTo(this.xpixel + this.widthpixel - this.radius, this.ypixel);
        this.ctx.quadraticCurveTo(this.xpixel + this.widthpixel, this.ypixel, this.xpixel + this.widthpixel, this.ypixel + this.radius);
        this.ctx.lineTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel - this.radius);
        this.ctx.quadraticCurveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel, this.xpixel + this.widthpixel - this.radius, this.ypixel + this.heightpixel);
        this.ctx.lineTo(this.xpixel + this.radius, this.ypixel + this.heightpixel);
        this.ctx.quadraticCurveTo(this.xpixel, this.ypixel + this.heightpixel, this.xpixel, this.ypixel + this.heightpixel - this.radius);
        this.ctx.lineTo(this.xpixel, this.ypixel + this.radius);
        this.ctx.quadraticCurveTo(this.xpixel, this.ypixel, this.xpixel + this.radius, this.ypixel);
        this.ctx.stroke();
    }
    _drawFrame() {
        this.ctx.strokeStyle = this.frame_color;
        this.ctx.lineWidth = this.border_width;
        if (this.radius > 0) {
            this._drawRadius();
        }
        else {
            this.ctx.strokeRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
    }
    _draw() {
        this._drawFrame();
    }
}