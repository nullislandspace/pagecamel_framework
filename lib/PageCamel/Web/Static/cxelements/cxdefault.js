class CXDefault {
    constructor(ctx, x, y, width, height) {
        this.ctx = ctx;
        this.xpos = x;
        this.ypos = y;
        this.width = width;
        this.height = height;
    }
    calcRelXToPixel(canvas_width, rel_x) {
        // calculate the x position of the element relative to the canvas
        return rel_x * canvas_width;
    }
    calcRelYToPixel(canvas_height, rel_y) {
        // calculate the y position of the element relative to the canvas
        return rel_y * canvas_height;
    }
    _getViewInfo() {
    }
    _getMinSize() {
    }
    _sgetMaxSize() {
    }
}