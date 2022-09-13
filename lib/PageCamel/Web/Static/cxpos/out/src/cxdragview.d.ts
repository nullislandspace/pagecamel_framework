import { CXDefaultView } from './mycxelements/cxdefaultview.js';
export declare class CXDragView extends CXDefaultView {
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative?: boolean, redraw?: boolean);
    _draw(): void;
}
