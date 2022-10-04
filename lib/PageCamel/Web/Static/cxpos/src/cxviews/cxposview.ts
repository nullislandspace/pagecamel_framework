import { CXTable } from "../cxadds/cxtable.js";
import { CXTextBox } from "../cxelements/cxtextbox.js";
import { CXDefaultView } from "./cxdefaultview.js";

export class CXPosView extends  CXDefaultView{
    protected _selected_table: CXTable | null;
    protected _selected_table_textbox: CXTextBox;
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._selected_table = null;
        this._selected_table_textbox = new CXTextBox(ctx, 0, 0, 0.15, 0.05, true, false);
        this._selected_table_textbox.text = "Table: ";
        this._elements.push(this._selected_table_textbox);
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
    
}