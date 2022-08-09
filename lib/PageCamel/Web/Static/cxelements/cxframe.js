class CXFrame extends CXDefault{
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.ctx = ctx;
        this.frame_color = "black";
        this.radius = 0;
        this.border_width = 1;
        this.hovering = false;
    }
    _drawRadius() {
        // draw rounded rectangle
        this.ctx.beginPath();
        this.ctx.moveTo(this._xpos + this.radius, this._ypos);
        this.ctx.lineTo(this._xpos + this._width - this.radius, this._ypos);
        this.ctx.quadraticCurveTo(this._xpos + this._width, this._ypos, this._xpos + this._width, this._ypos + this.radius);
        this.ctx.lineTo(this._xpos + this._width, this._ypos + this._height - this.radius);
        this.ctx.quadraticCurveTo(this._xpos + this._width, this._ypos + this._height, this._xpos + this._width - this.radius, this._ypos + this._height);
        this.ctx.lineTo(this._xpos + this.radius, this._ypos + this._height);
        this.ctx.quadraticCurveTo(this._xpos, this._ypos + this._height, this._xpos, this._ypos + this._height - this.radius);
        this.ctx.lineTo(this._xpos, this._ypos + this.radius);
        this.ctx.quadraticCurveTo(this._xpos, this._ypos, this._xpos + this.radius, this._ypos);
        this.ctx.stroke();
    }
    _drawFrame() {
        this.ctx.strokeStyle = this.frame_color;
        this.ctx.lineWidth = this.border_width;
        if (this.radius > 0) {
            this._drawRadius();
        }
        else {
            this.ctx.strokeRect(this._xpos, this._ypos, this._width, this._height);
        }
    }
    draw() {
        this._drawFrame();
    }
}