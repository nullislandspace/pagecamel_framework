class CXFrame {
    constructor(ctx, x, y, width, height) {
        this.ctx = ctx;
        this.frame_color = "black";
        this.xpos = x;
        this.ypos = y;
        this.width = width;
        this.height = height;
        this.radius = 0;
        this.hovering = false;
    }
    _drawRadius() {
        // draw rounded rectangle
        this.ctx.beginPath();
        this.ctx.moveTo(this.xpos + this.radius, this.ypos);
        this.ctx.lineTo(this.xpos + this.width - this.radius, this.ypos);
        this.ctx.quadraticCurveTo(this.xpos + this.width, this.ypos, this.xpos + this.width, this.ypos + this.radius);
        this.ctx.lineTo(this.xpos + this.width, this.ypos + this.height - this.radius);
        this.ctx.quadraticCurveTo(this.xpos + this.width, this.ypos + this.height, this.xpos + this.width - this.radius, this.ypos + this.height);
        this.ctx.lineTo(this.xpos + this.radius, this.ypos + this.height);
        this.ctx.quadraticCurveTo(this.xpos, this.ypos + this.height, this.xpos, this.ypos + this.height - this.radius);
        this.ctx.lineTo(this.xpos, this.ypos + this.radius);
        this.ctx.quadraticCurveTo(this.xpos, this.ypos, this.xpos + this.radius, this.ypos);
        this.ctx.stroke();
    }
    _drawFrame() {
        this.ctx.strokeStyle = this.frame_color;
        if (this.radius > 0) {
            this._drawRadius();
        }
        else {
            this.ctx.strokeRect(this.xpos, this.ypos, this.width, this.height);
        }
    }
    draw() {
        this._drawFrame();
    }
    checkClick(x, y) {
        // check if mouse click is inside the frame 
        if (x >= this.xpos && x <= this.xpos + this.width && y >= this.ypos && y <= this.ypos + this.height) {
            console.log("click inside frame");
            this.clickHandler();
        }
    }
    checkHover(x, y) {
        // check if mouse is inside the frame
        if (!this.hovering && x >= this.xpos && x <= this.xpos + this.width && y >= this.ypos && y <= this.ypos + this.height) {
            this.hoverInHandler();
            this.hovering = true;
        } else if (this.hovering) {
            this.hoverOutHandler();
            this.hovering = false;
        }

    }
    clickHandler() {
        // override this function in child classes to handle click events
    }
    hoverInHandler() {
        // override this function in child classes to handle hover events
    }
    hoverOutHandler() {
        // override this function in child classes to handle hover out events
    }
}