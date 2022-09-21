import { CXDefaultView } from './cxdefaultview.js';
import { CXDragAndDrop } from '../cxelements/cxdraganddrop.js';
export class CXDragView extends CXDefaultView {
    constructor(ctx, x = 0, y = 0, width = 1.0, height = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._draw_mode = 'none';
        this.border_width = 0.001;
        this.background_color = '#fff';
        this._draganddrop = new CXDragAndDrop(ctx, 0.1, 0.1, 0.1, 0.1, is_relative, false);
        this._draganddrop.border_width = 10;
        this._draganddrop.border_relative = false;
        this._draganddrop.attributes = {
            text: "Drag me",
            background_color: "#00ffff",
            border_color: "#ff0000",
        };
        console.log('get attributes:', this._draganddrop.attributes);
    }
    _initialize() {
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
    set draw_mode(mode) {
        this._draw_mode = mode;
    }
}
//# sourceMappingURL=cxdragview.js.map