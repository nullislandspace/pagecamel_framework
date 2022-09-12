//import { CXBox } from "./cxbox";
/*export*/ class CXDragView extends CXBox {
    constructor(ctx, x, y, width, height, name = "", is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, name, is_relative, redraw);
        this._draganddrop = new CXDragAndDrop(ctx, 0.1, 0.1, 0.1, 0.1, name, is_relative, false);
        this._draganddrop.radius = 0.2;
        this._draganddrop.text = "123";
        this._draganddrop.background_color = '#ff0000';
    }
    _draw() {
        super._draw();
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