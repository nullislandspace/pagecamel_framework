import { CXDefaultView } from './mycxelements/cxdefaultview.js';
import { CXDragAndDrop } from './mycxelements/cxdraganddrop.js';
export class CXDragView extends CXDefaultView {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.0;
        this.background_color = '#ff0000';
        this._draganddrop = new CXDragAndDrop(ctx, 0.1, 0.1, 0.1, 0.1, is_relative, false);
        this._draganddrop.text = "123";
        this._draganddrop.background_color = '#ff0000';
    }
    _draw() {
        super._draw();
        this._draganddrop.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    _handleEvent(event) {
        if (this._draganddrop.checkEvent(event)) {
            this._draganddrop.handleEvent(event);
            if (this._draganddrop.has_changed) {
                this._has_changed = true;
            }
        }
        this._tryRedraw();
        return this._has_changed;
    }
}
