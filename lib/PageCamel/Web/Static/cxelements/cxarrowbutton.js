class CXArrowButton extends CXButton {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
        this.arrow_color = "black";
        this.arrow_width = width;
        this.arrow_height = height;
        this.arrow_direction = "right";
    }
    _drawArrow() {
        this._ctx.fillStyle = this.arrow_color;
        this._ctx.beginPath();
        if (this.arrow_direction == "right") {
            // draw an arrow pointing to the right
            this._ctx.moveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this.arrow_width, this.ypixel + this.heightpixel / 2 - this.arrow_height / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this.arrow_width, this.ypixel + this.heightpixel / 2 + this.arrow_height / 2);
        }
        else if (this.arrow_direction == "left") {
            // draw an arrow pointing to the left
            this._ctx.moveTo(this.xpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this.arrow_width, this.ypixel + this.heightpixel / 2 - this.arrow_height / 2);
            this._ctx.lineTo(this.xpixel + this.arrow_width, this.ypixel + this.heightpixel / 2 + this.arrow_height / 2);
        }
        else if (this.arrow_direction == "up") {
            // draw an arrow pointing to the top
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this.arrow_width / 2, this.ypixel + this.arrow_height);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this.arrow_width / 2, this.ypixel + this.arrow_height);
        }
        else if (this.arrow_direction == "down") {
            // draw an arrow pointing to the bottom
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel + this.heightpixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this.arrow_width / 2, this.ypixel + this.heightpixel - this.arrow_height);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this.arrow_width / 2, this.ypixel + this.heightpixel - this.arrow_height);
        }
        this._ctx.closePath();
        this._ctx.fill();
    }
    _draw() {
        super._draw();
        this._drawArrow();
    }
}