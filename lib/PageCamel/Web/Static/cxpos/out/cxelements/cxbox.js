import { CXFrame } from "./cxframe.js";
export class CXBox extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._background_color = "green";
        this._gradient = [];
        this._first_gradient_color = "";
    }
    _drawBox() {
        this._ctx.fillStyle = this._background_color;
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
            this._ctx.fill();
        }
        else {
            var x = this.xpixel + Math.ceil(this._border_width_pixel / 2);
            var y = this.ypixel + Math.ceil(this._border_width_pixel / 2);
            var width = this.widthpixel - this._border_width_pixel;
            var height = this.heightpixel - this._border_width_pixel;
            this._ctx.fillRect(x, y, width, height);
        }
    }
    _draw() {
        this._drawBox();
    }
    set background_color(color) {
        this._background_color = color;
    }
    get background_color() {
        return this._background_color;
    }
    set gradient(gradient) {
        this._gradient = gradient;
        this._first_gradient_color = gradient[0];
    }
    get gradient() {
        return this._gradient;
    }
}
