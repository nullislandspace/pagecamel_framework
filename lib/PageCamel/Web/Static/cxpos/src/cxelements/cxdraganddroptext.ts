import { CXDragAndDropRect } from './cxdraganddroprect.js';
export class CXDragAndDropText extends CXDragAndDropRect {
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
    }
    protected _drawDragndrop(): void {
        this.font_size = 1.0;
        this._drawText();
    }
}