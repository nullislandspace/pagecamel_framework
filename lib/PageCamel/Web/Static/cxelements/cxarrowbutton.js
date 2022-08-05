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
            this.ctx.moveTo(this.xpos + this.width, this.ypos + this.height / 2);
            this.ctx.lineTo(this.xpos + this.width - this.arrow_width, this.ypos + this.height / 2 - this.arrow_height / 2);
            this.ctx.lineTo(this.xpos + this.width - this.arrow_width, this.ypos + this.height / 2 + this.arrow_height / 2);
        }
        else if (this.arrow_direction == "left") {
            // draw an arrow pointing to the left
            this.ctx.moveTo(this.xpos, this.ypos + this.height / 2);
            this.ctx.lineTo(this.xpos + this.arrow_width, this.ypos + this.height / 2 - this.arrow_height / 2);
            this.ctx.lineTo(this.xpos + this.arrow_width, this.ypos + this.height / 2 + this.arrow_height / 2);
        }
        else if (this.arrow_direction == "up") {
            // draw an arrow pointing to the top
            this.ctx.moveTo(this.xpos + this.width / 2, this.ypos);
            this.ctx.lineTo(this.xpos + this.width / 2 - this.arrow_width / 2, this.ypos + this.arrow_height);
            this.ctx.lineTo(this.xpos + this.width / 2 + this.arrow_width / 2, this.ypos + this.arrow_height);
        }
        else if (this.arrow_direction == "down") {
            // draw an arrow pointing to the bottom
            this.ctx.moveTo(this.xpos + this.width / 2, this.ypos + this.height);
            this.ctx.lineTo(this.xpos + this.width / 2 - this.arrow_width / 2, this.ypos + this.height - this.arrow_height);
            this.ctx.lineTo(this.xpos + this.width / 2 + this.arrow_width / 2, this.ypos + this.height - this.arrow_height);
        }
        this.ctx.closePath();
        this.ctx.fill();
    }
    draw() {
        this._drawButton();
        this._drawArrow();
    }
}