import { CXDefaultView } from './cxdefaultview.js';
import { CXDragAndDrop } from '../cxelements/cxdraganddrop.js';

export class CXDragView extends CXDefaultView {
    private _draganddrop: CXDragAndDrop;
    protected _draw_mode: string = 'none';
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.001;
        this.background_color = '#fff';
        this._draganddrop = new CXDragAndDrop(ctx, 0.1, 0.1, 0.1, 0.1, is_relative, false);
        this._draganddrop.border_width = 10;
        this._draganddrop.border_relative = false;
        this._draganddrop.attributes = {
            text: "Move me",
            background_color: "#00ffff",
            border_color: "#ff0000",
        };
        console.log('get attributes:', this._draganddrop.attributes);
    }
    protected _initialize(): void {

    }
    protected _draw(): void {
        super._draw();
        this._draganddrop.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    protected _handleEvent(event: Event): boolean {
        if (this._draganddrop.checkEvent(event)) {
            this._draganddrop.handleEvent(event);
            if (this._draganddrop.has_changed) {
                this._has_changed = true;
            }
        }
        this._tryRedraw();
        return this._has_changed;
    }
    /**
     * Set the draw mode of the view (rect, circle, img, text, select) for drawing a new dragable element
     * @param mode
     */
    set draw_mode(mode: string) {
        if (mode !== 'none' && mode !== 'select') {
            //show crosshair cursor
            this._ctx.canvas.style.cursor = 'crosshair';
            this._draganddrop.default_cursor = 'crosshair';
        }
        else {
            this._ctx.canvas.style.cursor = 'default';
            this._draganddrop.default_cursor = 'default';
        }
        this._draw_mode = mode;
    }
}