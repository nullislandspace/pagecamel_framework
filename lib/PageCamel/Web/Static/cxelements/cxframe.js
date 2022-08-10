class CXFrame extends CXDefault {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.frame_color = "black";
        this.radius = 0;
        this.border_width = 1;
        this.hovering = false;
    }
    _drawRadius(xpixel, ypixel, widthpixel, heightpixel) {
        // draw rounded rectangle
        this.ctx.beginPath();
        this.ctx.moveTo(xpixel + this.radius, ypixel);
        this.ctx.lineTo(xpixel + widthpixel - this.radius, ypixel);
        this.ctx.quadraticCurveTo(xpixel + widthpixel, ypixel, xpixel + widthpixel, ypixel + this.radius);
        this.ctx.lineTo(xpixel + widthpixel, ypixel + heightpixel - this.radius);
        this.ctx.quadraticCurveTo(xpixel + widthpixel, ypixel + heightpixel, xpixel + widthpixel - this.radius, ypixel + heightpixel);
        this.ctx.lineTo(xpixel + this.radius, ypixel + heightpixel);
        this.ctx.quadraticCurveTo(xpixel, ypixel + heightpixel, xpixel, ypixel + heightpixel - this.radius);
        this.ctx.lineTo(xpixel, ypixel + this.radius);
        this.ctx.quadraticCurveTo(xpixel, ypixel, xpixel + this.radius, ypixel);
        this.ctx.stroke();
    }
    _drawFrame(xpixel, ypixel, widthpixel, heightpixel) {
        this.ctx.strokeStyle = this.frame_color;
        this.ctx.lineWidth = this.border_width;
        if (this.radius > 0) {
            this._drawRadius(px, py, pwidth, pheight);
        }
        else {
            this.ctx.strokeRect(xpixel, ypixel, widthpixel, heightpixel);
        }
    }
    _draw(xpixel, ypixel, widthpixel, heightpixel) {
        this._drawFrame(xpixel, ypixel, widthpixel, heightpixel);
    }
}