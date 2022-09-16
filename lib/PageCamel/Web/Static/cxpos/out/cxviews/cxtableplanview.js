import { CXDefaultView } from './cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
import * as cxe from '../cxelements/cxelements.js';
export class CXTablePlanView extends CXDefaultView {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._elements = [];
        super.border_width = 0.001;
        var dragview = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
        var add_btn = new cxe.CXButton(ctx, 0.8, 0.0, 0.2, 0.2, is_relative, false);
        this._elements.push(dragview);
        this._elements.push(add_btn);
        this.background_color = '#A9A9A9';
    }
    _draw() {
        super._draw();
        this._elements.forEach(element => {
            element.draw(super._px, super._py, super._pwidth, super._pheight);
        });
    }
    _handleEvent(event) {
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this._has_changed = true;
                }
            }
        });
        this._tryRedraw();
        return this._has_changed;
    }
}
