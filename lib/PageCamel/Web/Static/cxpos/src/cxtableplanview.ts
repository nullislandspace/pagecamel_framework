import { CXDefaultView } from './mycxelements/cxdefaultview.js';
import { CXDragView } from './cxdragview.js';

export class CXTablePlanView extends CXDefaultView {
    /* Table Plan json data: 
    { 
        text: "Room 1",
        background_color: "#ffff",
        background_img: "hash",
        text_color: "#000000",
        tables: [
            {
                text: "Table 1",
                background_color: "#ffff",
                background_img: "hash",
                text_color: "#000000",
                x: 0,
                y: 0,
                width: 100,
                height: 100,
            }. . .
        ]. . .
    }
    */
    protected _dragview: CXDragView;
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.0;
        this._dragview = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
    }
    _draw() {
        super._draw();
        this._dragview.draw(this._px, this._py, this._pwidth, this._pheight);
    }
}