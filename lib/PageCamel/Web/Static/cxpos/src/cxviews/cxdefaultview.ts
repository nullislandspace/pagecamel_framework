import { CXBox } from "../cxelements/cxbox.js";
import { CXTable } from "../cxadds/cxtable.js";
export class CXDefaultView extends CXBox {
    private _table: CXTable;
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._table = new CXTable();
    }
    set Table(table: CXTable) {
        this._table = table;
    }
    get Table(): CXTable {
        return this._table;
    }
}