import { CXDefaultView } from './cxdefaultview.js';
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
        super.border_width = 0.0;
        this._dragview = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
        this._dragview.background_color = '#00FF00'
    }
    _draw() {
        super._draw();
        this._dragview.draw(super._px, super._py, super._pwidth, super._pheight);
    }
    protected _handleEvent(event: Event): boolean {
        if (this._dragview.checkEvent(event)) {
            this._dragview.handleEvent(event);
            if (this._dragview.has_changed) {
                this._has_changed = true;
            }
        }
        this._tryRedraw();
        return this._has_changed;
    }
}