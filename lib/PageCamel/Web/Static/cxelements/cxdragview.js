class CXDragView extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._draganddrop = new CXDragAndDrop(ctx, 0.1, 0.1, 0.1, 0.1, is_relative, false);
        this._draganddrop.text = "1321";
    }
    _draw() {
        this._draganddrop.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    handleEvent(event) {
        if (this._draganddrop.checkEvent(event)) {
            this._draganddrop.handleEvent(event);
            if (this._draganddrop._has_changed) {
                this._has_changed = true;
            }
        }
        this._tryRedraw();
    }

}