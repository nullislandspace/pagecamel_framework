import { CXDefaultView } from './mycxelements/cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
export declare class CXTablePlanView extends CXDefaultView {
    protected _dragview: CXDragView;
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative?: boolean, redraw?: boolean);
    _draw(): void;
}
