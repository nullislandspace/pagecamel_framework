import { CXBox } from "./cxbox.js";
import { CXTable } from "./cxtable.js";
export class CXDefaultView extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._name = "CXDefaultView";
        this._table = new CXTable();
    }
    set Table(table) {
        this._table = table;
    }
    get Table() {
        return this._table;
    }
    onBackButtonClicked() {
    }
}
