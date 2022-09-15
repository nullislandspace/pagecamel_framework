import { CXBox } from "./cxbox.js";
import { CXTable } from "./cxtable.js";
export declare class CXDefaultView extends CXBox {
    protected _table: CXTable;
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative?: boolean, redraw?: boolean);
    set Table(table: CXTable);
    get Table(): CXTable;
    onBackButtonClicked(): void;
}
