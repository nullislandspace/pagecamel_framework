import { CXTable } from "../cxadds/cxtable.js";
import { CXButton } from "../cxelements/cxbutton.js";
import { CXTextBox } from "../cxelements/cxtextbox.js";
import { CXDefaultView } from "./cxdefaultview.js";

export class CXPosView extends CXDefaultView {
    protected _selected_table: CXTable | null = null;
    protected _selected_table_textbox: CXButton = new CXButton(this._ctx, 0, 0, 0.1, 0.1, true, false);
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initialize();
    }
    protected _initialize() {
        this._elements.push(this._selected_table_textbox);
        this._tryRedraw();
    }
    set selectedTable(table: CXTable | null) {
        this._selected_table = table;
        console.log("Pos Selected table: ", table);
        if (table != null) {
        }
    }
    get selectedTable(): CXTable | null {
        return this._selected_table;
    }
}