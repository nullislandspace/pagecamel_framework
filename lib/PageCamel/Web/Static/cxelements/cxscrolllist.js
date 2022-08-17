class CXScrollList extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.radius = 10;

        this.scroll_bar = new CXScrollBar(ctx, 0.95, 0.0, 0.05, 1.0, true, false);
        this.scroll_bar.rows = 20;
        this.scroll_bar.rows_per_page = 5;
        this.scroll_bar.scrollbar.radius = 10;
        this.scroll_bar.radius = 10;
        this.border_width = 2;
        this._elements.push(this.scroll_bar);
    }
    _checkMouseMove(x, y) {
        if (this._mouse_down) {
            return true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this._mouse_over = true;
            return true;
        } else if (this._mouse_over) {
            this._mouse_over = false;
            return true;
        }
        return false;
    }
    _draw() {
        console.log("redraw");
        this._ctx.clearRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        this._ctx.fillStyle = "white";
        this._ctx.fillRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        super._draw(); // draws the frame of the parent class
        this._elements.forEach(element => {
            element.draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
        );
    }
    handleEvent(event) {
        var redraw = false;
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    redraw = true;
                }
            }
        });
        if (redraw && this._redraw) {
            this._draw();
        }
    }
}