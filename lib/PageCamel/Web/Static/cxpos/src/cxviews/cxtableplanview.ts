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

        var gap: number = 0.01;
        var button_height: number = 0.05;
        this._dragview = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
        var undo_btn = new cxe.CXButton(this._ctx, gap, 1 - button_height - gap, 0.05, button_height, true, false);
        undo_btn.attributes = this._special_func_buttons;
        undo_btn.setSquareSize(null, undo_btn.height);
        undo_btn.text = '⮪';

        var redo_btn = new cxe.CXButton(this._ctx, undo_btn.xpos + undo_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        redo_btn.attributes = this._special_func_buttons;
        redo_btn.setSquareSize(null, redo_btn.height);
        redo_btn.text = '⮫';

        var select_btn = new cxe.CXButton(this._ctx, redo_btn.xpos + redo_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        select_btn.attributes = this._special_func_buttons;
        select_btn.setSquareSize(null, select_btn.height);
        select_btn.onClick = this._onDrawButtonClick;
        select_btn.text = '🖰'
        select_btn.name = 'select';
        this._draw_buttons.push(select_btn);

        var draw_rect_btn = new cxe.CXButton(this._ctx, select_btn.xpos + select_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_rect_btn.attributes = this._special_func_buttons;
        draw_rect_btn.setSquareSize(null, draw_rect_btn.height);
        draw_rect_btn.onClick = this._onDrawButtonClick;
        draw_rect_btn.name = 'rect';
        draw_rect_btn.text = '⬛';
        this._draw_buttons.push(draw_rect_btn);

        var draw_circle_btn = new cxe.CXButton(this._ctx, draw_rect_btn.xpos + draw_rect_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_circle_btn.attributes = this._special_func_buttons;
        draw_circle_btn.setSquareSize(null, draw_circle_btn.height);
        draw_circle_btn.onClick = this._onDrawButtonClick;
        draw_circle_btn.name = 'circle';
        draw_circle_btn.text = '⬤';
        this._draw_buttons.push(draw_circle_btn);

        var draw_img_btn = new cxe.CXButton(this._ctx, draw_circle_btn.xpos + draw_circle_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_img_btn.attributes = this._special_func_buttons;
        draw_img_btn.setSquareSize(null, draw_img_btn.height);
        draw_img_btn.onClick = (obj: cxe.CXButton) => this._onAddImageClick(obj);
        draw_img_btn.name = 'img';
        draw_img_btn.text = '🖼';
        this._draw_buttons.push(draw_img_btn);

        var draw_text_btn = new cxe.CXButton(this._ctx, draw_img_btn.xpos + draw_img_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_text_btn.attributes = this._special_func_buttons;
        draw_text_btn.setSquareSize(null, draw_text_btn.height);
        draw_text_btn.onClick = this._onDrawButtonClick;
        draw_text_btn.name = 'text';
        draw_text_btn.text = '📝';
        this._draw_buttons.push(draw_text_btn);



        var duplicate_btn = new cxe.CXButton(this._ctx, draw_text_btn.xpos + draw_text_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        duplicate_btn.attributes = this._special_func_buttons;
        duplicate_btn.setSquareSize(null, duplicate_btn.height);
        duplicate_btn.onClick = (obj: cxe.CXButton) => this._onDuplicateClick(obj);
        duplicate_btn.text = '⎘';

        var delete_btn = new cxe.CXButton(this._ctx, duplicate_btn.xpos + duplicate_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        delete_btn.attributes = this._special_func_buttons;
        delete_btn.setSquareSize(null, delete_btn.height);
        delete_btn.onClick = () => this._dragview.deleteSelectedDragAndDrop();
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
    protected _onDuplicateClick(obj: cxe.CXButton): void {
        this._dragview.duplicateSelectedDragAndDrop();
    }

    protected _onDrawButtonClick(obj: cxe.CXButton): void {
        this._dragview.draw_mode = obj.name;
        this._draw_buttons.forEach((button: { name: string; border_width: number; }) => {
            if (button.name != obj.name) {
                //set to default border width
                button.border_width = this._special_func_buttons.border_width;
            }
        }
        );
        obj.border_width = 0.1;
        this._tryRedraw();
    }
    /**
     * When Image button is clicked, open file dialog
     */
    private _onAddImageClick(obj: cxe.CXButton): void {
        this._onDrawButtonClick(obj);
        this.onAddImageClick(obj);
    }
    /**
     * Gets called when the user wants do add an draganddrop image
     */
    public onAddImageClick(obj: cxe.CXButton): void {
        //override this
    }

    /**
     * Callback when the image is loaded
     * @param img - file reader result from the image
     */
    public onImageSelected = (img: string): void => {
        console.log('dragview onImageSelected', this._dragview);
        this._dragview.draganddropImage = img;
    }
}