import { CXDragAndDrop } from './cxdraganddrop';
class CXDragAndDropEllipse extends CXDragAndDrop {
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
    }
    _draw() {
        this._ctx.beginPath();
        //this._ctx.ellipse(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel, 0, 0, 2 * Math.PI);
        this._ctx.stroke();
    }
}
