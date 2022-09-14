import { CXDefault } from "./mycxelements/cxdefault.js";
export declare class CXTestView extends CXDefault {
    protected viewelements: any[];
    private _leftlist;
    private _infotext;
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative?: boolean, redraw?: boolean);
    private _initialize;
    handleEvent(e: Event): boolean;
    protected _draw(): void;
    private _onListSelect;
}
