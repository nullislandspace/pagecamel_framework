import { CXDefaultView } from './cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
import * as cxe from '../cxelements/cxelements.js';


export class CXTablePlanView extends CXDefaultView {
    /* Table Plan json data: 
    [{ 
        text: "Room 1",
        background_color: "#ffff",
        background_img: "hash",
        text_color: "#000000",
        tables: [
            {
                text: "Table 1",
                background_color: "#ffff",
                background_img: "hash",
                text_color: "#000000",
                x: 0,
                y: 0,
                width: 100,
                height: 100,
            },
            . . .
        ]. . .
    }]
    */
    protected _initialize(): void {
        this._border_width = 0.0;
        var dragview: CXDragView = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
        function onDrawButtonClick(obj: cxe.CXButton) {
            console.log('draw button', obj.name, 'clicked');
            obj.border_width = 0.1;
            dragview.draw_mode = obj.name;
        }
        var undo_btn = new cxe.CXButton(this._ctx, 0.01, 0.94, 0.05, 0.05, true, false);
        undo_btn.attributes = this._special_func_buttons;
        undo_btn.text = '⮪';

        var redo_btn = new cxe.CXButton(this._ctx, 0.07, 0.94, 0.05, 0.05, true, false);
        redo_btn.attributes = this._special_func_buttons;
        redo_btn.text = '⮫';

        var draw_rect_btn = new cxe.CXButton(this._ctx, 0.13, 0.94, 0.05, 0.05, true, false);
        draw_rect_btn.attributes = this._special_func_buttons;
        draw_rect_btn.onClick = onDrawButtonClick;
        draw_rect_btn.name = 'rect';
        draw_rect_btn.text = '⬛';

        var draw_circle_btn = new cxe.CXButton(this._ctx, 0.19, 0.94, 0.05, 0.05, true, false);
        draw_circle_btn.attributes = this._special_func_buttons;
        draw_circle_btn.onClick = onDrawButtonClick;
        draw_circle_btn.name = 'circle';
        draw_circle_btn.text = '⬤';

        var draw_img_btn = new cxe.CXButton(this._ctx, 0.25, 0.94, 0.05, 0.05, true, false);
        draw_img_btn.attributes = this._special_func_buttons;
        draw_img_btn.onClick = onDrawButtonClick;
        draw_img_btn.name = 'img';
        draw_img_btn.text = '🖼';

        var draw_text_btn = new cxe.CXButton(this._ctx, 0.31, 0.94, 0.05, 0.05, true, false);
        draw_text_btn.attributes = this._special_func_buttons;
        draw_text_btn.onClick = onDrawButtonClick;
        draw_text_btn.name = 'text';
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
    protected _handleEvent(event: Event): boolean {
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