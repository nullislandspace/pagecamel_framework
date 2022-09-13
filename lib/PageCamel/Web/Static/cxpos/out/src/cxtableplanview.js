import { CXDefaultView } from './mycxelements/cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
export class CXTablePlanView extends CXDefaultView {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.0;
        this._dragview = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
    }
    _draw() {
        super._draw();
        this._dragview.draw(this._px, this._py, this._pwidth, this._pheight);
    }
}
