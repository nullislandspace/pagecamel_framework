import { PCWebsocket } from "../../../pcwebsocket/src/websocket.js";
import { CXTable } from "../cxadds/cxtable.js";
import { CXButton } from "../cxelements/cxbutton.js";
import { CXButtonGrid } from "../cxelements/cxbuttongrid.js";
import { CXNumPad } from "../cxelements/cxelements.js";
import { CXScrollList } from "../cxelements/cxscrolllist.js";
import { CXTextBox } from "../cxelements/cxtextbox.js";
import { CXDefaultView } from "./cxdefaultview.js";

export class CXPosView extends CXDefaultView {
    protected _selected_table: CXTable | null = null;
    private _selected_table_button: CXButton;
    private _invoice_list: CXScrollList;
    private _numfield: CXButtonGrid;
    protected _padding: number = 0.01;
    protected _processArticlesCB(): void {
    }
    protected _processInvoiceCB(): void {
    }
    protected _processTableUpdateCB(): void {
    }
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._selected_table_button = new CXButton(this._ctx, this._padding, 0.01, 0.1, 0.05, true, false);
        this._invoice_list = new CXScrollList(this._ctx, this._padding, this._selected_table_button.ypos + this._selected_table_button.height + 0.01, 0.48, 0.5, true, false);
        
        // add numfield
        this._numfield = new CXButtonGrid(this._ctx, 0.1, this._invoice_list.ypos + this._invoice_list.height + 0.01, 0.1, 1, true, false);
        var clear_btn_attr = {...{text: 'C'} , ...this._special_func_buttons}
        this._numfield.buttons_text_block = [[null, null, clear_btn_attr], ['7', '8', '9'], ['4', '5', '6'], ['1', '2', '3'], ['+/-', '0', ',']];
        this._numfield.height = 1 - this._numfield.ypos - 0.01;
        this._numfield.setSquareSize();
        this._numfield.xpos = this._invoice_list.xpos + this._invoice_list.width - this._numfield.width; // align with new width      
        
        //this._left_button_bar = new CXButtonGrid();
        
        this._selected_table_button.text = "Table";
        this._selected_table_button.attributes = this._special_func_buttons;
        this._invoice_list.background_color = "#ffffffff";
        this._elements.push(this._selected_table_button);
        this._elements.push(this._invoice_list);
        this._elements.push(this._numfield);

    }
    protected _procArticles(): void {
        this._processArticlesCB();
    }
    protected _procInvoice(): void {
        this._processArticlesCB();
    }

    protected _handleWebsocketConnect(): void {
        // this.sendMsgGetArticles();
        return;
    }

    /* sendMsgGetArticles(): void {
        console.log('get articles');
        if (this._pcwebsocket != null) {
            
        }
    } */
    protected _sendMsgProcessInvoice(invoice: object): void {
        if (this._pcwebsocket != null) {
            this._pcwebsocket.send('PROCESSINVOICE', JSON.stringify(invoice), true);
        }
    }
    set selectedTable(table: CXTable | null) {
        this._selected_table = table;
        console.log("Pos Selected table: ", table);
        if (table != null) {
            this._selected_table_button.text = "Table: " + table.name;
        }
    }

    get selectedTable(): CXTable | null {
        return this._selected_table;
    }
    set pcwebsocket(pcwebsocket: PCWebsocket | null) {
        super.pcwebsocket = pcwebsocket;
        if (this._pcwebsocket != null) {
            this._pcwebsocket.register('ARTICLES', [this._procArticles.bind(this)]);
            this._pcwebsocket.register('INVOICE', [this._procInvoice.bind(this)]);
        }
    }
    get pcwebsocket(): PCWebsocket | null {
        return super.pcwebsocket;
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