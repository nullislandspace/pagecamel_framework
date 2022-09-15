import { CXDefaultView } from './mycxelements/cxdefaultview.js';
export class CXDragView extends CXDefaultView {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.0;
        this.background_color = '#ff0000';
    }
    _draw() {
        super._draw();
    }
}
