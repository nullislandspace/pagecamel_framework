import { PCWebsocket } from "../../../pcwebsocket/src/websocket.js";
import { CXTable } from "../cxadds/cxtable.js";
import { CXButton } from "../cxelements/cxbutton.js";
import { CXButtonGrid } from "../cxelements/cxbuttongrid.js";
import { CXArrowButton, CXNumPad } from "../cxelements/cxelements.js";
import { CXScrollList } from "../cxelements/cxscrolllist.js";
import { CXTextBox } from "../cxelements/cxtextbox.js";
import { CXDefaultView } from "./cxdefaultview.js";

export class CXPosView extends CXDefaultView {
    private _selected_table: CXTable | null = null;
    private _select_table_button: CXButton;
    private _logout_button: CXButton;
    private _selected_table_textbox: CXTextBox;
    private _invoice_list: CXScrollList;
    private _numfield: CXButtonGrid;
    private _left_button_bar: CXButtonGrid;
    private _right_button_bar: CXButtonGrid;

    private _page_up_arrow: CXArrowButton;
    private _page_down_arrow: CXArrowButton;


    private _sum_text: CXTextBox;

    private _input_field: CXTextBox;

    protected _padding: number = 0.01;

    protected _processArticlesCB(): void {
    }
    protected _processInvoiceCB(): void {
    }
    protected _processTableUpdateCB(): void {
    }
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        // button to Left press to select new table
        this._select_table_button = new CXButton(this._ctx, this._padding, 0.01, 0.1, 0.05, true, false);
        this._select_table_button.attributes = this._special_func_buttons;
        this._select_table_button.text = "Tisch";


        // textbox top left shows which table is selected
        this._selected_table_textbox = new CXTextBox(this._ctx, this._select_table_button.xpos + this._select_table_button.width + this._padding, this._padding, 0.1, 0.05, true, false);
        this._selected_table_textbox.text_alignment = "left";
        this._selected_table_textbox.attributes = this._textbox;

        // invoice list
        this._invoice_list = new CXScrollList(this._ctx, this._padding, this._select_table_button.ypos + this._select_table_button.height + 0.01, 0.48, 0.5, true, false);
        this._invoice_list.background_color = "#ffffffff";

        // logout button
        this._logout_button = new CXButton(this._ctx, this._invoice_list.xpos + this._invoice_list.width - 0.1, this._padding, 0.1, 0.05, true, false);
        this._logout_button.attributes = this._special_func_buttons;
        this._logout_button.text = "Abmelden";


        // add numfield
        this._numfield = new CXButtonGrid(this._ctx, 0.1, this._invoice_list.ypos + this._invoice_list.height + 0.01, 0.1, 1, true, false);
        var clear_btn_attr = { ...{ text: 'C' }, ...this._special_func_buttons }
        this._numfield.buttons_text_block = [[null, null, clear_btn_attr], ['7', '8', '9'], ['4', '5', '6'], ['1', '2', '3'], ['+/-', '0', ',']];
        this._numfield.height = 1 - this._numfield.ypos - 0.01;
        this._numfield.setSquareSize();
        this._numfield.xpos = this._invoice_list.xpos + this._invoice_list.width - this._numfield.width; // align with new width      
        this._numfield.onClick = (object: CXButtonGrid, key: string | null): void => this._handleNumfieldInput(object, key);

        // left aligned buttons
        this._left_button_bar = new CXButtonGrid(this._ctx, this._padding, this._numfield.ypos + this._numfield.height / 5, 0.11, this._numfield.height - this._numfield.height / 5, true, false);
        var bar_btn_attr = { ...{ text: 'BAR', font_size: 0.3 }, ...this._bar_buttons };
        this._left_button_bar.buttonAttributes = { ...{ font_size: 0.3 }, ...this._general_func_buttons };
        this._left_button_bar.buttons_text_block = [[bar_btn_attr], [{ text: 'Rechnung' }], [{ text: 'Splitten' }], [{ text: 'ZWS' }]];
        this._left_button_bar.onClick = (object: CXButtonGrid, key: string | null): void => {
            if (key == 'BAR') {
                this._onBarButtonClick();
            }
            /* else if (key == 'Rechnung') {
                this._onBarButtonClick();
            } */
        }

        // right aligned buttons
        this._right_button_bar = new CXButtonGrid(this._ctx, this._numfield.xpos - this._padding - 0.08, this._left_button_bar.ypos, 0.08, this._left_button_bar.height, true, false);
        this._right_button_bar.buttonAttributes = { ...{ font_size: 0.3 }, ...this._general_func_buttons };
        this._right_button_bar.buttons_text_block = [[{ text: 'Storno' }], [{ text: 'Rabatt' }], [{ text: 'PLU' }], [{ text: 'X' }]];
        this._right_button_bar.onClick = (object: CXButtonGrid, key: string | null): void => this._rightButtonBarClick(object, key);
        var arrow_attr = { background_color: '#fff' }
        // arrows bellow scroll list
        this._page_up_arrow = new CXArrowButton(this._ctx, this._padding, this._invoice_list.ypos + this._invoice_list.height + this._padding, 0.07, 0.06, true, false);
        this._page_up_arrow.arrow_direction = 'up';
        this._page_up_arrow.attributes = arrow_attr;

        this._page_down_arrow = new CXArrowButton(this._ctx, this._page_up_arrow.xpos + this._page_up_arrow.width + this._padding, this._invoice_list.ypos + this._invoice_list.height + this._padding, 0.07, 0.06, true, false);
        this._page_down_arrow.arrow_direction = 'down';
        this._page_down_arrow.attributes = arrow_attr;

        // sum textbox
        this._sum_text = new CXTextBox(this._ctx, this._page_down_arrow.xpos + this._page_down_arrow.width + this._padding, this._invoice_list.ypos + this._invoice_list.height + this._padding, 0.2, 0.06, true, false);
        this._sum_text.background_color = "#00000000";
        this._sum_text.border_color = "#00000000";
        this._sum_text.text_color = "#ff0000ff";
        this._sum_text.text_alignment = "left";
        this._sum_text.font_size = 0.8;
        this._sum_text.text = "0,00";

        //number input field
        this._input_field = new CXTextBox(this._ctx, this._numfield.xpos, this._numfield.ypos, this._numfield.width / 3 * 2, this._numfield.height / 5 - this._numfield.gap / 3, true, false);
        this._input_field.attributes = this._textbox;

        this._elements.push(this._input_field);
        this._elements.push(this._selected_table_textbox);
        this._elements.push(this._page_up_arrow);
        this._elements.push(this._page_down_arrow);
        this._elements.push(this._left_button_bar);
        this._elements.push(this._right_button_bar);
        this._elements.push(this._select_table_button);
        this._elements.push(this._invoice_list);
        this._elements.push(this._numfield);
        this._elements.push(this._sum_text);
        this._elements.push(this._logout_button);
    }
    private _handleNumfieldInput(object: object, key: string | null): void {
        console.log('key: ' + key);
        // handle key input
        if (key != null) {
            if (key == 'C') {
                this._input_field.text = '';
            }
            else if (key == '+/-') {
                if (this._input_field.text.indexOf('-') > -1) {
                    this._input_field.text = this._input_field.text.replace('-', '');
                }
                else {
                    this._input_field.text = '-' + this._input_field.text;
                }
            }
            else if (this._input_field.text.includes('×')) {
                // prevents from adding numbers behind multiplier
                return;
            }
            else if (key == ',') {
                if (this._input_field.text.indexOf(',') > -1) {
                }
                else {
                    this._input_field.text += ',';
                }
            }

            else if (key == '0') {
                if (this._input_field.text.length == 0) {
                }
                else {
                    this._input_field.text += '0';
                }
            }
            else if (parseInt(key) >= 0 && parseInt(key) <= 9) {
                this._input_field.text += key;
            }
            //remove digits after comma if more than 2
            if (this._input_field.text.includes(',')) {
                var comma_index = this._input_field.text.indexOf(',');
                if (this._input_field.text.length - comma_index > 3) {
                    this._input_field.text = this._input_field.text.substring(0, comma_index + 3);
                }
            }
            // color text red if negative
            if (this._input_field.text.indexOf('-') > -1) {
                this._input_field.text_color = '#ff0000ff';
            }
            else {
                this._input_field.text_color = '#000000ff';
            }
            this._has_changed = true;
            this._tryRedraw();
        }

    }
    private _rightButtonBarClick(object: CXButtonGrid, key: string | null): void {
        if (key == 'X' && this._input_field.text.includes(',') == false && this._input_field.text.length > 0) {
            if (this._input_field.text.includes('×')) {
                this._input_field.text = this._input_field.text.replace('×', '');
            } else {
                this._input_field.text += '×';
            }
        }
        this._has_changed = true;
        this._tryRedraw();
    }


    private _onBarButtonClick(): void {
        this.onBarButtonClick();
    }
    /**
     * Callback function to handle bar button click
     */
    public onBarButtonClick(): void {
        console.log("Override onBarButtonClick callback function");
    }
    set selectedTable(table: CXTable | null) {
        this._selected_table = table;
        if (table != null) {
            this._selected_table_textbox.text = String(table.number);
            this._has_changed = true;
        }
        this._tryRedraw();
    }

    get selectedTable(): CXTable | null {
        return this._selected_table;
    }
    /**
     * Set Callback for processing the Articles which is received from the server
     */
    set processArticlesCB(cb: () => void) {
        this._processArticlesCB = cb;
    }
    get processArticlesCB(): () => void {
        return this._processArticlesCB;
    }
    /**
     * Set Callback for processing the invoice which is received from the server
     */
    set processInvoiceCB(cb: () => void) {
        this._processInvoiceCB = cb;
    }
    get processInvoiceCB(): () => void {
        return this._processInvoiceCB;
    }
}