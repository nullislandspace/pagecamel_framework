import { CXDragAndDrop } from './cxdraganddrop.js';
export class CXDragAndDropEllipse extends CXDragAndDrop {
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
    }
    protected _drawDragndrop(): void {
        var center_x: number = this._xpixel + this._widthpixel / 2;
        var center_y: number = this._ypixel + this._heightpixel / 2;
        var radius_x: number = this._widthpixel / 2
        var radius_y: number = this._heightpixel / 2
        this._ctx.beginPath();
        this._ctx.ellipse(center_x, center_y, radius_x, radius_y, 0, 0, 2 * Math.PI);
        this._ctx.fillStyle = this._background_color;
        this._ctx.closePath();
        this._ctx.fill();
        
        this._ctx.beginPath();
        this._ctx.ellipse(center_x, center_y, Math.abs(radius_x - this._border_width / 4), Math.abs(radius_y - this._border_width / 4), 0, 0, 2 * Math.PI);
        this._ctx.lineWidth = this._border_width_pixel / 2;
        this._ctx.strokeStyle = this._border_color;
        this._ctx.closePath();
        this._ctx.stroke();
        this._drawText();
    }
}