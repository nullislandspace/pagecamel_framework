class CXArrowButton extends CXButton {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
        this._arrow_color = "black";
        this._arrow_width = width;
        this._arrow_height = height;
        this._arrow_direction = "right";
    }
    _drawArrow() {
        this._ctx.fillStyle = this._arrow_color;
        this._ctx.beginPath();
        if (this._arrow_direction == "right") {
            // draw an arrow pointing to the right
            this._ctx.moveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this._arrow_width, this.ypixel + this.heightpixel / 2 - this._arrow_height / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this._arrow_width, this.ypixel + this.heightpixel / 2 + this._arrow_height / 2);
        }
        else if (this._arrow_direction == "left") {
            // draw an arrow pointing to the left
            this._ctx.moveTo(this.xpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this._arrow_width, this.ypixel + this.heightpixel / 2 - this._arrow_height / 2);
            this._ctx.lineTo(this.xpixel + this._arrow_width, this.ypixel + this.heightpixel / 2 + this._arrow_height / 2);
        }
        else if (this._arrow_direction == "up") {
            // draw an arrow pointing to the top
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this._arrow_width / 2, this.ypixel + this._arrow_height);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this._arrow_width / 2, this.ypixel + this._arrow_height);
        }
        else if (this._arrow_direction == "down") {
            // draw an arrow pointing to the bottom
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel + this.heightpixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this._arrow_width / 2, this.ypixel + this.heightpixel - this._arrow_height);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this._arrow_width / 2, this.ypixel + this.heightpixel - this._arrow_height);
        }
        this._ctx.closePath();
        this._ctx.fill();
    }
    _draw() {
        super._draw();
        this._drawArrow();
    }
    get arrow_color() {
        return this._arrow_color;
    }
    set arrow_color(value) {
        this._arrow_color = value;
    }
    get arrow_width() {
        return this._arrow_width;
    }
    set arrow_width(value) {
        this._arrow_width = value;
    }
    get arrow_height() {
        return this._arrow_height;
    }
    set arrow_height(value) {
        this._arrow_height = value;
    }
    get arrow_direction() {
        return this._arrow_direction;
    }
    set arrow_direction(value) {
        this._arrow_direction = value;
    }
}