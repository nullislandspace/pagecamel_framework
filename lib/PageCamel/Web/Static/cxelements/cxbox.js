class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.box_color = "green";
    }
    _drawBox() {
        ctx.fillStyle = this.box_color;
        super._draw();
        if (this.radius > 0) {
            //fill rounded rectangle
            ctx.fill();
        }
        else {
            //fill rectangle
            ctx.fillRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
    }
    _draw() {
        this._drawBox();
    }
}