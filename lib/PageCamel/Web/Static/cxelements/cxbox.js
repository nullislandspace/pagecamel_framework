class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._background = "green";
        this._gradient = [];
        this._first_gradient_color = "";
    }
    _drawBox() {
        ctx.fillStyle = this._background;
        if(this._gradient.length > 0) {
            var grd = this._ctx.createLinearGradient(this.xpixel, this.ypixel, this.xpixel, this.ypixel + this.heightpixel);
            var step_size = 1 / (this._gradient.length - 1);
            for (var i = 0; i < this._gradient.length; i++) {
                grd.addColorStop(i * step_size, this._gradient[i]);
            }
            this._ctx.fillStyle = grd;
        }
        super._draw();
        if (this._radius > 0) {
            //fill rounded rectangle
            ctx.fill();
        }
        else {
            //fill rectangle
            ctx.fillRect(this.xpixel + Math.ceil(this._border_width / 2), this.ypixel + Math.ceil(this._border_width / 2), this.widthpixel - this._border_width, this.heightpixel - this._border_width);
        }
    }
    _draw() {
        this._drawBox();
    }
    /**
     * @param {string} color - Color of the box
     */
    set background(color) {
        this._background = color;
    }
    get background() {
        return this._background;
    }
    /**
     * @param {array} gradient - Gradient
     * @description Gradient is an array of hex color values
     * @default []
     * @example
     * // Example of a gradient
     * var gradient = ["#ff0000", "#00ff00", "#0000ff"];
     */
    set gradient(gradient) {
        this._gradient = gradient;
        this._first_gradient_color = gradient[0];
    }
    get gradient() {
        return this._gradient;
    }
}