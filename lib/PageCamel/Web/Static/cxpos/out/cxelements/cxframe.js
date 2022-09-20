import { CXDefault } from "./cxdefault.js";
export class CXFrame extends CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._border_color = "black";
        this._radius = 0;
        this._radius_pixel = 0;
        this._border_width = 0.02;
        this._border_width_pixel = 0;
        this._border_relative = is_relative;
    }
    isInside(x, y) {
        return (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel);
    }
    _convertFrameToPixel() {
        if (this._border_relative) {
            this._border_width_pixel = this._calcRelXToPixel(this._border_width, this._heightpixel);
        }
        else {
            this._border_width_pixel = this._border_width;
        }
        this._radius_pixel = this._calcRelXToPixel(this._radius, this._heightpixel);
    }
    _convertToPixel() {
        this._convertFrameToPixel();
    }
    _drawRadius() {
        this._ctx.beginPath();
        this._ctx.moveTo(this.xpixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2), this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2), this.xpixel + this.widthpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2), this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2), this.xpixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2));
        if (this._border_width_pixel > 0) {
            this._ctx.stroke();
        }
    }
    _drawFrame() {
        this._ctx.strokeStyle = this._border_color;
        this._ctx.lineWidth = this._border_width_pixel;
        if (this._radius_pixel > 0) {
            this._drawRadius();
        }
        else {
            if (this._border_width_pixel > 0) {
                this._ctx.strokeRect(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2), this.widthpixel - this._border_width_pixel, this.heightpixel - this._border_width_pixel);
            }
        }
    }
    _draw() {
        this._drawFrame();
    }
    set border_color(color) {
        this._border_color = color;
    }
    get border_color() {
        return this._border_color;
    }
    set radius(r) {
        this._radius = r;
    }
    get radius() {
        return this._radius;
    }
    set border_width(w) {
        this._border_width = w;
    }
    get border_width() {
        return this._border_width;
    }
    set border_relative(state) {
        this._border_relative = state;
    }
}
//# sourceMappingURL=cxframe.js.map