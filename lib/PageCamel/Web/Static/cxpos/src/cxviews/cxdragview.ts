import { CXDefaultView } from './cxdefaultview.js';
import { CXDragAndDrop } from '../cxelements/cxdraganddrop.js';

export class CXDragView extends CXDefaultView {
    protected _draw_mode: string = 'none';
    private _draganddrops: Array<CXDragAndDrop> = [];
    protected _draw_rect: CXDragAndDrop | null;
    protected _drawMouseDownX: number | null = null;
    protected _drawMouseDownY: number | null = null;

    protected _count: number = 0;
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.001;
        this.background_color = '#fff';
        this._draw_rect = null;
    }
    protected _initialize(): void {

    }
    protected _draw(): void {
        super._draw();
        this._draganddrops.forEach(draganddrop => {
            draganddrop.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        });
        if (this._draw_rect) {
            console.log("draw rect");
            this._draw_rect.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        }
    }
    protected _finishCreation(): void {
        if (this._draw_rect && this._drawMouseDownX && this._drawMouseDownY) {
            this._draganddrops.push(this._draw_rect);
            this._draw_rect = null;
            this._drawMouseDownX = null;
            this._drawMouseDownY = null;
        }
    }
    protected _handleEvent(event: Event): boolean {
        var [x, y] = this._eventToXY(event as MouseEvent);
        var xrel = this._calcPixelXToRel(x, this._widthpixel);
        var yrel = this._calcPixelYToRel(y, this._heightpixel);
        if (xrel > 0 && xrel < 1 && yrel > 0 && yrel < 1) {
            if (event.type === 'mousedown') {
                if (this._draw_mode === 'rect') {
                    this._drawMouseDownX = xrel;
                    this._drawMouseDownY = yrel;
                    this._draw_rect = new CXDragAndDrop(this._ctx, xrel, yrel, 0.001, 0.001, true, false);
                    this._draw_rect.name = 'rect' + this._count;
                    this._draw_rect.text = String(this._draw_rect.name);
                    this._count++;
                    this._draw_rect.border_relative = false;
                    this._draw_rect.border_width = 15;
                    this._draw_rect.resizeable = false;
                }
            }
            else if (event.type === 'mousemove') {
                if (this._draw_rect && this._drawMouseDownX && this._drawMouseDownY) {
                    // handles the drawing of the new dragable element
                    if (xrel > this._drawMouseDownX) {
                        this._draw_rect.xpos = this._drawMouseDownX;
                        this._draw_rect.width = xrel - this._drawMouseDownX;
                    }
                    else {
                        this._draw_rect.xpos = xrel;
                        this._draw_rect.width = this._drawMouseDownX - xrel;
                    }
                    if (yrel > this._drawMouseDownY) {
                        this._draw_rect.ypos = this._drawMouseDownY;
                        this._draw_rect.height = yrel - this._drawMouseDownY;
                    }
                    else {
                        this._draw_rect.ypos = yrel;
                        this._draw_rect.height = this._drawMouseDownY - yrel;
                    }
                }
            }
            else if (event.type === 'mouseup') {
                this._finishCreation();
            }
            this._has_changed = true;
        }
        //loop through all drag and drop elements reverse order
        if (this._draw_mode === 'select') {
            var handled = false;
            var handled_index = -1;
            for (var i = this._draganddrops.length - 1; i >= 0; i--) {
                var draganddrop = this._draganddrops[i];
                if (draganddrop.checkEvent(event)) {
                    if (handled === false) {
                        draganddrop.handleEvent(event);
                    }
                    if (draganddrop.has_changed) {
                        console.log('draganddrop has changed' + draganddrop.name);
                        handled = true;
                        handled_index = i;
                        this._has_changed = true;

                    }
                }
            }
            if (handled) {
                //remove draganddrop that was handled and add it to the end of the list
                var handled_draganddrop = this._draganddrops[handled_index];
                this._draganddrops.splice(handled_index, 1);
                this._draganddrops.push(handled_draganddrop);
                for (var i = 0; i < this._draganddrops.length - 1; i++) {
                    this._draganddrops[i].show_resize_frame = false;
                    this._draganddrops[i].move_dragndrop = false;
                }
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
        this._finishCreation();
        if (mode !== 'none' && mode !== 'select') {
            //show crosshair cursor
            this._ctx.canvas.style.cursor = 'crosshair';
            //this._draganddrop.default_cursor = 'crosshair';
            //this._draganddrop.show_resize_frame = false;
            this._draganddrops.forEach(draganddrop => {
                draganddrop.show_resize_frame = false;
                draganddrop.resizeable = false;
            });
        }
        else {
            this._ctx.canvas.style.cursor = 'default';
            this._draganddrops.forEach(draganddrop => {
                draganddrop.resizeable = true;
            });
            //this._draganddrop.default_cursor = 'default';
        }
        this._draw_mode = mode;
        this._tryRedraw();
    }
    get draw_mode(): string {
        return this._draw_mode;
    }
}