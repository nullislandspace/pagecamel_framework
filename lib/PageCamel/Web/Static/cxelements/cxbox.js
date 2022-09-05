class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._background = "green";
        this._gradient = [];
        this._first_gradient_color = "";
    }
    _drawBox() {
        this._ctx.fillStyle = this._background;
        if (this._gradient.length > 0) {
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
            console.log("fill rounded rectangle with color: " + this._background);
            this._ctx.fill();
        }
        else {
            //fill rectangle
            var x = this.xpixel + Math.ceil(this._border_width / 2);
            var y = this.ypixel + Math.ceil(this._border_width / 2);
            var width = this.widthpixel - this._border_width;
            var height = this.heightpixel - this._border_width;
            this._ctx.fillRect(x, y, width, height);
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