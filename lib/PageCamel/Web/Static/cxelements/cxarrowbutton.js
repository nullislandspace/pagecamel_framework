class CXArrowButton extends CXButton {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.arrow_color = "black";
        this.arrow_width = width;
        this.arrow_height = height;
        this.arrow_direction = "right";
    }
    _drawArrow() {
        this.ctx.fillStyle = this.arrow_color;
        this.ctx.beginPath();
        if (this.arrow_direction == "right") {
            // draw an arrow pointing to the right
            this.ctx.moveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel / 2);
            this.ctx.lineTo(this.xpixel + this.widthpixel - this.arrow_width, this.ypixel + this.heightpixel / 2 - this.arrow_height / 2);
            this.ctx.lineTo(this.xpixel + this.widthpixel - this.arrow_width, this.ypixel + this.heightpixel / 2 + this.arrow_height / 2);
        }
        else if (this.arrow_direction == "left") {
            // draw an arrow pointing to the left
            this.ctx.moveTo(this.xpixel, this.ypixel + this.heightpixel / 2);
            this.ctx.lineTo(this.xpixel + this.arrow_width, this.ypixel + this.heightpixel / 2 - this.arrow_height / 2);
            this.ctx.lineTo(this.xpixel + this.arrow_width, this.ypixel + this.heightpixel / 2 + this.arrow_height / 2);
        }
        else if (this.arrow_direction == "up") {
            // draw an arrow pointing to the top
            this.ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel);
            this.ctx.lineTo(this.xpixel + this.widthpixel / 2 - this.arrow_width / 2, this.ypixel + this.arrow_height);
            this.ctx.lineTo(this.xpixel + this.widthpixel / 2 + this.arrow_width / 2, this.ypixel + this.arrow_height);
        }
        else if (this.arrow_direction == "down") {
            // draw an arrow pointing to the bottom
            this.ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel + this.heightpixel);
            this.ctx.lineTo(this.xpixel + this.widthpixel / 2 - this.arrow_width / 2, this.ypixel + this.heightpixel - this.arrow_height);
            this.ctx.lineTo(this.xpixel + this.widthpixel / 2 + this.arrow_width / 2, this.ypixel + this.heightpixel - this.arrow_height);
        }
        this.ctx.closePath();
        this.ctx.fill();
    }
    _draw() {
        super._draw();
        this._drawArrow();
    }
}