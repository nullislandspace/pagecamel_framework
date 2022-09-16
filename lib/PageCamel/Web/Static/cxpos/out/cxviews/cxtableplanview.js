import { CXDefaultView } from './cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
export class CXTablePlanView extends CXDefaultView {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.border_width = 0.0;
        this._dragview = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
        this._dragview.background_color = '#00FF00';
    }
    _draw() {
        super._draw();
        this._dragview.draw(super._px, super._py, super._pwidth, super._pheight);
    }
    _handleEvent(event) {
        if (this._dragview.checkEvent(event)) {
            this._dragview.handleEvent(event);
            if (this._dragview.has_changed) {
                this._has_changed = true;
            }
        }
        this._tryRedraw();
        return this._has_changed;
    }
}
