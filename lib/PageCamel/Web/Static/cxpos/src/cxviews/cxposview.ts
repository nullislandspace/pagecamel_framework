import { PCWebsocket } from "../../../pcwebsocket/src/websocket.js";
import { CXTable } from "../cxadds/cxtable.js";
import { CXTextBox } from "../cxelements/cxtextbox.js";
import { CXDefaultView } from "./cxdefaultview.js";

export class CXPosView extends CXDefaultView {
    protected _selected_table: CXTable | null = null;
    protected _selected_table_textbox: CXTextBox = new CXTextBox(this._ctx, 0, 0, 0.1, 0.1, true, false);
    protected _processArticlesCB(): void {
    }
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initialize();
    }
    protected _initialize() {
        this._selected_table_textbox.text = "Table: ";
        this._elements.push(this._selected_table_textbox);
        this._tryRedraw();
    }
    protected _procArticles() {
        this._processArticlesCB();
    }
    sendMsgGetArticles() {
        console.log('get articles');
        if (this._pcwebsocket != null) {
            this._pcwebsocket.send('GETARTICLES', '', true);
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
        }
    }
    get pcwebsocket(): PCWebsocket | null {
        return super.pcwebsocket;
    }
    set processArticlesCB(cb: () => void) {
        this._processArticlesCB = cb;
    }
    get processArticlesCB(): () => void {
        return this._processArticlesCB;
    }
}