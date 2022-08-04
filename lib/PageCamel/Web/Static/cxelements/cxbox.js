class CXBox extends CXFrame {
    constructor(ctx) {
        super(ctx);
        this.box_color = "green";
    }
    drawBox(x, y, width, height) {
        ctx.fillStyle = this.box_color;
        ctx.fillRect(x, y, width, height);
        this.drawFrame(x, y, width, height);
    }
}