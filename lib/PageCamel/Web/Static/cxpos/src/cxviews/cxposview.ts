import { PCWebsocket } from "../../../pcwebsocket/src/websocket.js";
import { CXTable } from "../cxadds/cxtable.js";
import { CXTextBox } from "../cxelements/cxtextbox.js";
import { CXDefaultView } from "./cxdefaultview.js";

export class CXPosView extends CXDefaultView {
    protected _selected_table: CXTable | null = null;
    protected _selected_table_textbox: CXTextBox = new CXTextBox(this._ctx, 0, 0, 0.1, 0.1, true, false);
    protected _processArticlesCB(): void {
    }
    protected _processInvoiceCB(): void {
    }
    protected _processTableUpdateCB(): void {
    }
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initialize();
    }
    protected _initialize(): void {
        this._selected_table_textbox.text = "Table: ";
        this._elements.push(this._selected_table_textbox);
        this._tryRedraw();
    }
    protected _procArticles(): void {
        this._processArticlesCB();
    }
    protected _procInvoice(): void {
        this._processArticlesCB();
    }
    sendMsgGetArticles(): void {
        console.log('get articles');
        console.log('??????????????????????????????????? get articles');
        if (this._pcwebsocket != null) {
            console.log('################################## get articles');
            this._pcwebsocket.send('GETARTICLES', '', false);
        }
    }
    protected _sendMsgProcessInvoice(invoice: object): void {
        if (this._pcwebsocket != null) {
            this._pcwebsocket.send('PROCESSINVOICE', JSON.stringify(invoice), true);
        }
    }
    set selectedTable(table: CXTable | null) {
        this._selected_table = table;
        console.log("Pos Selected table: ", table);
        if (table != null) {
            this._selected_table_textbox.text = "Table: " + table.name;
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