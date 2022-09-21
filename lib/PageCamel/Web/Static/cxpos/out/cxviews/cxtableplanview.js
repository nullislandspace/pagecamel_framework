import { CXDefaultView } from './cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
import * as cxe from '../cxelements/cxelements.js';
export class CXTablePlanView extends CXDefaultView {
    _initialize() {
        var dragview = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
        var undo_btn = new cxe.CXButton(this._ctx, 0.01, 0.94, 0.05, 0.05, true, false);
        undo_btn.attributes = Object.assign({}, this._special_func_buttons);
        undo_btn.text = '⮪';
        var redo_btn = new cxe.CXButton(this._ctx, 0.07, 0.94, 0.05, 0.05, true, false);
        redo_btn.radius = 0.1;
        redo_btn.gradient = ['#80b3ffff', '#1193eeff'];
        redo_btn.border_color = '#eeeeeeff';
        redo_btn.border_width = 0.02;
        redo_btn.text = '⮫';
        var draw_rect_btn = new cxe.CXButton(this._ctx, 0.13, 0.94, 0.05, 0.05, true, false);
        draw_rect_btn.attributes = this._special_func_buttons;
        draw_rect_btn.text = '⬛';
        var draw_circle_btn = new cxe.CXButton(this._ctx, 0.19, 0.94, 0.05, 0.05, true, false);
        draw_circle_btn.attributes = this._special_func_buttons;
        draw_circle_btn.text = '⬤';
        var draw_img_btn = new cxe.CXButton(this._ctx, 0.25, 0.94, 0.05, 0.05, true, false);
        draw_img_btn.attributes = this._special_func_buttons;
        draw_img_btn.text = '🖼';
        var draw_text_btn = new cxe.CXButton(this._ctx, 0.31, 0.94, 0.05, 0.05, true, false);
        draw_text_btn.attributes = this._special_func_buttons;
        draw_text_btn.text = '📝';
        var duplicate_btn = new cxe.CXButton(this._ctx, 0.37, 0.94, 0.05, 0.05, true, false);
        duplicate_btn.attributes = this._special_func_buttons;
        duplicate_btn.text = '📋';
        var delete_btn = new cxe.CXButton(this._ctx, 0.43, 0.94, 0.05, 0.05, true, false);
        delete_btn.attributes = this._special_func_buttons;
        delete_btn.text = '🗑';
        this._elements.push(dragview);
        this._elements.push(undo_btn);
        this._elements.push(redo_btn);
        this._elements.push(draw_rect_btn);
        this._elements.push(draw_circle_btn);
        this._elements.push(draw_img_btn);
        this._elements.push(draw_text_btn);
        this._elements.push(duplicate_btn);
        this._elements.push(delete_btn);
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
//# sourceMappingURL=cxtableplanview.js.map