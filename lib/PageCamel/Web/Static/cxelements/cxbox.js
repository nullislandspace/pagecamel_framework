class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.box_color = "green";
    }
    _drawBox() {
        ctx.fillStyle = this.box_color;
        this._drawFrame();
        if (this.radius > 0) {
            //fill rounded rectangle
            ctx.fill();
        }
        else {
            //fill rectangle
            ctx.fillRect(this.xpos, this.ypos, this.width, this.height);
        }
    }
    draw() {
        this._drawBox();
    }
}