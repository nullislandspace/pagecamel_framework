import { CXButton } from "./cxbutton.js";
export class CXArrowButton extends CXButton {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._arrow_color = "black";
        this._arrow_width = 0.8;
        this._arrow_height = 0.8;
        this._arrow_direction = "right";
        this._arrow_width_pixel = 0;
        this._arrow_height_pixel = 0;
        this._name = "CXArrowButton";
    }
    _drawArrow() {
        this._ctx.fillStyle = this._arrow_color;
        this._ctx.beginPath();
        if (this._arrow_direction == "right") {
            this._ctx.moveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 - this._arrow_height_pixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 + this._arrow_height_pixel / 2);
        }
        else if (this._arrow_direction == "left") {
            this._ctx.moveTo(this.xpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 - this._arrow_height_pixel / 2);
            this._ctx.lineTo(this.xpixel + this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 + this._arrow_height_pixel / 2);
        }
        else if (this._arrow_direction == "up") {
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this._arrow_width_pixel / 2, this.ypixel + this._arrow_height_pixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this._arrow_width_pixel / 2, this.ypixel + this._arrow_height_pixel);
        }
        else if (this._arrow_direction == "down") {
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel + this.heightpixel - this.heightpixel / 2 + this._arrow_height_pixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this._arrow_width_pixel / 2, this.ypixel + this.heightpixel - this._arrow_height_pixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this._arrow_width_pixel / 2, this.ypixel + this.heightpixel - this._arrow_height_pixel);
        }
        this._ctx.closePath();
        this._ctx.fill();
    }
    _draw() {
        super._draw();
        this._arrow_height_pixel = this._calcRelYToPixel(this._arrow_height, this._heightpixel);
        this._arrow_width_pixel = this._calcRelXToPixel(this._arrow_width, this._widthpixel);
        this._drawArrow();
    }
    get arrow_color() {
        return this._arrow_color;
    }
    set arrow_color(color) {
        this._arrow_color = color;
    }
    get arrow_width() {
        return this._arrow_width;
    }
    set arrow_width(width) {
        this._arrow_width = width;
    }
    get arrow_height() {
        return this._arrow_height;
    }
    set arrow_height(height) {
        this._arrow_height = height;
    }
    get arrow_direction() {
        return this._arrow_direction;
    }
    set arrow_direction(direction) {
        this._arrow_direction = direction;
    }
}
