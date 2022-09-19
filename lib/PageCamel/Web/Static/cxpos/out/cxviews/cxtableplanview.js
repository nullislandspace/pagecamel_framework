import { CXDefaultView } from './cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
import * as cxe from '../cxelements/cxelements.js';
export class CXTablePlanView extends CXDefaultView {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._elements = [];
        super.border_width = 0.001;
        var dragview = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
        var blue_btn_attributes = {
            radius: 0.1,
            gradient: ['#4fbcff', '#009dff'],
            border_color: '#4fbcff',
            hover_border_color: '#009dff'
        };
        var undo_btn = new cxe.CXButton(ctx, 0.02, 0.93, 0.05, 0.05, is_relative, false);
        undo_btn.attributes = blue_btn_attributes;
        undo_btn.text = '⮪';
        undo_btn.name = 'undo_btn';
        var redo_btn = new cxe.CXButton(ctx, 0.08, 0.93, 0.05, 0.05, is_relative, false);
        redo_btn.attributes = blue_btn_attributes;
        redo_btn.text = '⮫';
        redo_btn.name = 'redo_btn';
        this._elements.push(dragview);
        this._elements.push(undo_btn);
        this._elements.push(redo_btn);
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
