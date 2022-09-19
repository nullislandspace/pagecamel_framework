import { CXDefaultView } from './cxdefaultview.js';
import { CXDragView } from './cxdragview.js';
import * as cxe from '../cxelements/cxelements.js';


export class CXTablePlanView extends CXDefaultView {
    /* Table Plan json data: 
    [{ 
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
            },
            . . .
        ]. . .
    }]
    */
    protected _elements: any[] = [];
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.border_width = 0.001;
        var dragview: CXDragView = new CXDragView(ctx, 0.0, 0.0, 0.8, 0.8, is_relative, false);
        var add_btn: cxe.CXButton = new cxe.CXButton(ctx, 0.8, 0.0, 0.2, 0.2, is_relative, false);
        this._elements.push(dragview);
        this._elements.push(add_btn);
        this.background_color = '#A9A9A9';
    }
    _draw() {
        super._draw();
        this._elements.forEach(element => {
            element.draw(super._px, super._py, super._pwidth, super._pheight);
        });
    }
    protected _handleEvent(event: Event): boolean {
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this._has_changed = true;
                }
            }
        });
        this._tryRedraw();
        return this._has_changed;
    }
}