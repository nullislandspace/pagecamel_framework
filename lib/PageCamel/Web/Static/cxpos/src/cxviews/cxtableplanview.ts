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
    protected _draw_buttons: cxe.CXButton[] = [];
    protected _dragview: CXDragView = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initialize();
    }
    protected _initialize(): void {
        this._onDrawButtonClick = this._onDrawButtonClick.bind(this);
        this._draw_buttons = []
        this._border_width = 0.0;

        this._dragview = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
        var undo_btn = new cxe.CXButton(this._ctx, 0.01, 0.94, 0.05, 0.05, true, false);
        undo_btn.attributes = this._specialFuncButtons;
        undo_btn.text = '⮪';

        var redo_btn = new cxe.CXButton(this._ctx, 0.07, 0.94, 0.05, 0.05, true, false);
        redo_btn.attributes = this._specialFuncButtons;
        redo_btn.text = '⮫';

        var select_btn = new cxe.CXButton(this._ctx, 0.13, 0.94, 0.05, 0.05, true, false);
        select_btn.attributes = this._specialFuncButtons;
        select_btn.onClick = this._onDrawButtonClick;
        select_btn.text = '🖰'
        select_btn.name = 'select';
        this._draw_buttons.push(select_btn);

        var draw_rect_btn = new cxe.CXButton(this._ctx, 0.19, 0.94, 0.05, 0.05, true, false);
        draw_rect_btn.attributes = this._specialFuncButtons;
        draw_rect_btn.onClick = this._onDrawButtonClick;
        draw_rect_btn.name = 'rect';
        draw_rect_btn.text = '⬛';
        this._draw_buttons.push(draw_rect_btn);

        var draw_circle_btn = new cxe.CXButton(this._ctx, 0.25, 0.94, 0.05, 0.05, true, false);
        draw_circle_btn.attributes = this._specialFuncButtons;
        draw_circle_btn.onClick = this._onDrawButtonClick;
        draw_circle_btn.name = 'circle';
        draw_circle_btn.text = '⬤';
        this._draw_buttons.push(draw_circle_btn);

        var draw_img_btn = new cxe.CXButton(this._ctx, 0.31, 0.94, 0.05, 0.05, true, false);
        draw_img_btn.attributes = this._specialFuncButtons;
        draw_img_btn.onClick = this._onDrawButtonClick;
        draw_img_btn.name = 'img';
        draw_img_btn.text = '🖼';
        this._draw_buttons.push(draw_img_btn);

        var draw_text_btn = new cxe.CXButton(this._ctx, 0.37, 0.94, 0.05, 0.05, true, false);
        draw_text_btn.attributes = this._specialFuncButtons;
        draw_text_btn.onClick = this._onDrawButtonClick;
        draw_text_btn.name = 'text';
        draw_text_btn.text = '📝';
        this._draw_buttons.push(draw_text_btn);



        var duplicate_btn = new cxe.CXButton(this._ctx, 0.43, 0.94, 0.05, 0.05, true, false);
        duplicate_btn.attributes = this._specialFuncButtons;
        duplicate_btn.text = '📋';

        var delete_btn = new cxe.CXButton(this._ctx, 0.49, 0.94, 0.05, 0.05, true, false);
        delete_btn.attributes = this._specialFuncButtons;
        delete_btn.text = '🗑';

        this._elements.push(this._dragview);

        this._elements.push(undo_btn);
        this._elements.push(redo_btn);
        this._elements.push(select_btn);
        this._elements.push(draw_rect_btn);
        this._elements.push(draw_circle_btn);
        this._elements.push(draw_img_btn);
        this._elements.push(draw_text_btn);
        this._elements.push(duplicate_btn);
        this._elements.push(delete_btn);
    }
    protected _onDrawButtonClick(obj: cxe.CXButton): void {
        this._dragview.draw_mode = obj.name;
        this._draw_buttons.forEach((button: { name: string; border_width: number; }) => {
            if (button.name != obj.name) {
                button.border_width = this._specialFuncButtons.border_width;
                console.log('set border width to', this._specialFuncButtons.border_width, 'for', button.name);
            }
        }
        );
        obj.border_width = 0.1;
        this._tryRedraw();
    }
}