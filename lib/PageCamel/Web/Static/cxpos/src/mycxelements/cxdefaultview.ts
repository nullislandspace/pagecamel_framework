import { CXBox } from "./cxbox.js";
import { CXTable } from "./cxtable.js";
export class CXDefaultView extends CXBox {
    protected _table: CXTable;
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._name = "CXDefaultView";
    }
    set Table(table: CXTable) {
        this._table = table;
    }
    get Table(): CXTable {
        return this._table;
    }
    public onBackButtonClicked() {

    }
}