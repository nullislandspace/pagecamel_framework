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
    protected _editElements: any[] = [];
    protected _draw_buttons: cxe.CXButton[] = [];
    protected _dragview: CXDragView = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
    protected _edit_btn: cxe.CXButton = new cxe.CXButton(this._ctx, 0.85, 0.5, 0.1, 0.1, true, false);
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initialize();
    }
    protected _initialize(): void {
        this._border_width = 0.0;
        this._dragview = new CXDragView(this._ctx, 0.0, 0.0, 0.8, 0.8, true, false);
        this._dragview.onDragAndDropClick = (obj: cxe.CXButton) => this.onTableSelected(obj);
        this._initializeEditButtons();
        /*         const color_palet = new cxe.CXNumPad(this._ctx, 0.85, 0.5, 0.1, 0.1, this._is_relative, false);
                color_palet.buttons_text_block = [
                    [{ text: '1', gradient: ['#00ffff', '#ffff00'], onClick: (obj: cxe.CXButton) => this._changeColor(obj) }],
                    [{ text: '3', gradient: ['#ff0000', '#ffff00'], onClick: (obj: cxe.CXButton) => this._changeColor(obj) }]
                ];
                color_palet.gap = 0.01;
        
                this._elements.push(color_palet); */
        this._edit_btn = new cxe.CXButton(this._ctx, 0.01, 0.94, 0.1, 0.05, true, false);
        this._edit_btn.attributes = this._special_func_buttons;
        this._edit_btn.text = "Edit";
        this._edit_btn.onClick = (obj: cxe.CXButton) => this._edit(true);



        this._elements.push(this._edit_btn);
        this._elements.push(this._dragview);

    }
    private _initializeEditButtons() {
        this._onDrawButtonClick = this._onDrawButtonClick.bind(this);
        this._draw_buttons = []

        var gap: number = 0.01;
        var button_height: number = 0.05;
        var undo_btn = new cxe.CXButton(this._ctx, gap, 1 - button_height - gap, 0.05, button_height, true, false);

        undo_btn.attributes = this._special_func_buttons;
        undo_btn.setSquareSize(null, undo_btn.height);
        undo_btn.text = '⮪';

        const redo_btn = new cxe.CXButton(this._ctx, undo_btn.xpos + undo_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        redo_btn.attributes = this._special_func_buttons;
        redo_btn.setSquareSize(null, redo_btn.height);
        redo_btn.text = '⮫';

        const select_btn = new cxe.CXButton(this._ctx, redo_btn.xpos + redo_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        select_btn.attributes = this._special_func_buttons;
        select_btn.setSquareSize(null, select_btn.height);
        select_btn.onClick = this._onDrawButtonClick;
        select_btn.text = '🖰'
        select_btn.name = 'select';
        this._draw_buttons.push(select_btn);

        const draw_rect_btn = new cxe.CXButton(this._ctx, select_btn.xpos + select_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_rect_btn.attributes = this._special_func_buttons;
        draw_rect_btn.setSquareSize(null, draw_rect_btn.height);
        draw_rect_btn.onClick = this._onDrawButtonClick;
        draw_rect_btn.name = 'rect';
        draw_rect_btn.text = '⬛';
        this._draw_buttons.push(draw_rect_btn);

        const draw_circle_btn = new cxe.CXButton(this._ctx, draw_rect_btn.xpos + draw_rect_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_circle_btn.attributes = this._special_func_buttons;
        draw_circle_btn.setSquareSize(null, draw_circle_btn.height);
        draw_circle_btn.onClick = this._onDrawButtonClick;
        draw_circle_btn.name = 'circle';
        draw_circle_btn.text = '⬤';
        this._draw_buttons.push(draw_circle_btn);

        const draw_img_btn = new cxe.CXButton(this._ctx, draw_circle_btn.xpos + draw_circle_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_img_btn.attributes = this._special_func_buttons;
        draw_img_btn.setSquareSize(null, draw_img_btn.height);
        draw_img_btn.onClick = (obj: cxe.CXButton) => this._onAddImageClick(obj);
        draw_img_btn.name = 'img';
        draw_img_btn.text = '🖼';
        this._draw_buttons.push(draw_img_btn);

        const draw_text_btn = new cxe.CXButton(this._ctx, draw_img_btn.xpos + draw_img_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        draw_text_btn.attributes = this._special_func_buttons;
        draw_text_btn.setSquareSize(null, draw_text_btn.height);
        draw_text_btn.onClick = this._onDrawButtonClick;
        draw_text_btn.name = 'text';
        draw_text_btn.text = '📝';
        this._draw_buttons.push(draw_text_btn);



        const duplicate_btn = new cxe.CXButton(this._ctx, draw_text_btn.xpos + draw_text_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        duplicate_btn.attributes = this._special_func_buttons;
        duplicate_btn.setSquareSize(null, duplicate_btn.height);
        duplicate_btn.onClick = (obj: cxe.CXButton) => this._onDuplicateClick(obj);
        duplicate_btn.text = '⎘';

        const delete_btn = new cxe.CXButton(this._ctx, duplicate_btn.xpos + duplicate_btn.width + gap, 1 - button_height - gap, 0.05, button_height, true, false);
        delete_btn.attributes = this._special_func_buttons;
        delete_btn.setSquareSize(null, delete_btn.height);
        delete_btn.onClick = () => this._dragview.deleteSelectedDragAndDrop();
        delete_btn.text = '🗑';

        const background_img_btn = new cxe.CXButton(this._ctx, delete_btn.xpos + delete_btn.width + gap, 1 - button_height - gap, 0.13, button_height, true, false);
        background_img_btn.attributes = this._special_func_buttons;
        background_img_btn.onClick = (obj: cxe.CXButton) => this._onAddBackgroundImageClick(obj);
        background_img_btn.text = '🖻 Background';

        const cancel_edit_btn = new cxe.CXButton(this._ctx, 1.0 - 0.11, 1.0 - 0.06, 0.1, 0.05, true, false);
        cancel_edit_btn.attributes = this._special_func_buttons;
        cancel_edit_btn.onClick = (obj: cxe.CXButton) => this._edit(false);
        cancel_edit_btn.text = '🗙 Cancel';

        const save_edit_btn = new cxe.CXButton(this._ctx, 1.0 - 0.22, 1.0 - 0.06, 0.1, 0.05, true, false);
        save_edit_btn.attributes = this._special_func_buttons;
        save_edit_btn.onClick = (obj: cxe.CXButton) => this._save();
        save_edit_btn.text = '💾 Save';


        this._elements.push(undo_btn);
        this._elements.push(redo_btn);
        this._elements.push(select_btn);
        this._elements.push(draw_rect_btn);
        this._elements.push(draw_circle_btn);
        this._elements.push(draw_img_btn);
        this._elements.push(draw_text_btn);
        this._elements.push(duplicate_btn);
        this._elements.push(delete_btn);
        this._elements.push(background_img_btn);
        this._elements.push(cancel_edit_btn);
        this._elements.push(save_edit_btn);


        this._editElements.push(undo_btn);
        this._editElements.push(redo_btn);
        this._editElements.push(select_btn);
        this._editElements.push(draw_rect_btn);
        this._editElements.push(draw_circle_btn);
        this._editElements.push(draw_img_btn);
        this._editElements.push(draw_text_btn);
        this._editElements.push(duplicate_btn);
        this._editElements.push(delete_btn);
        this._editElements.push(background_img_btn);
        this._editElements.push(cancel_edit_btn);
        this._editElements.push(save_edit_btn);
        this._edit(false);
    }
    private _save(): void {
        console.log('get all drag and drop elements', this._dragview.getAllDragAndDrops());
        this._edit(false);

    }

    private _onAddBackgroundImageClick(obj: cxe.CXButton): void {
        this.onAddBackgroundImageClick(obj);
    }
    protected _onDuplicateClick(obj: cxe.CXButton): void {
        this._dragview.duplicateSelectedDragAndDrop();
    }

    /**
     * disble or enable edit mode
     * @param active - true to enable edit mode and false to disable
     */
    protected _edit(active: boolean): void {
        this._editElements.forEach(element => {
            element.active = active;
        });
        this._dragview.allow_editing = active;
        this._edit_btn.active = !active;
        this._has_changed = true;
        this._dragview.draw_mode = 'none';
        this._draw_buttons.forEach(element => {
            element.border_width = this._special_func_buttons.border_width;
        });
        this._tryRedraw();
    }
    /**
     * gets called when any of the buttons which are responsible for drawing a draganddrop element is clicked
     * @param obj - the button which was clicked
     */
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
     * Gets called when the user wants do change the dragview background image
     */
    public onAddBackgroundImageClick(obj: cxe.CXButton): void {
        //override this
    }

    /**
     * Callback when the image is loaded
     * @param img - file reader result from the image
     */
    public onImageSelected = (img: string): void => {
        this._dragview.draganddropImage = img;
    }
    /**
     * Callback when the background image is loaded
     * @param img - file reader result from the image
     */
    public onBackgroundImageSelected = (img: string): void => {
        this._dragview.background_image = img;
    }
    private _changeColor(obj: cxe.CXButton): void {
        if (this._dragview.selectedDragAndDrop != null) {
            this._dragview.selectedDragAndDrop.gradient = [...obj.gradient];
        }
        this._has_changed = true;
        this._tryRedraw();
    }
    set tables(tables: object[]) {
        this._dragview.draganddrops = tables;
    }
    onTableSelected = (table: cxe.CXButton): void => {
        console.log('table selected', table);
    }
}
