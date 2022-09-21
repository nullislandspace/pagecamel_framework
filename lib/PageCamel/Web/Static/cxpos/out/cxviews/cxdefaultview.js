import { CXBox } from "../cxelements/cxbox.js";
import { CXTable } from "../cxadds/cxtable.js";
export class CXDefaultView extends CXBox {
    constructor(ctx, x = 0, y = 0, width = 1.0, height = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._general_func_buttons = {
            radius: 0.1,
            gradient: ['#80b3ffff', '#1193eeff'],
            border_color: '#eeeeeeff',
            border_width: 0.02,
        };
        this._special_func_buttons = {
            radius: 0.1,
            gradient: ['#80b3ffff', '#1193eeff'],
            border_color: '#eeeeeeff',
            border_width: 0.02,
        };
        this._bar_buttons = {
            radius: 0.1,
            gradient: ['#87de87ff', '#008000ff'],
            border_color: '#eeeeeeff',
            border_width: 0.02,
        };
        this._table = new CXTable();
        this.background_color = '#b3b3b3ff';
        this._initialize();
    }
    _initialize() {
        console.warn("Overwrite the defaultview._initialize function");
    }
    ;
    _handleEvent(event) {
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
    _draw() {
        super._draw();
        this._elements.forEach(element => {
            element.draw(super._px, super._py, super._pwidth, super._pheight);
        });
    }
    set Table(table) {
        this._table = table;
    }
    get Table() {
        return this._table;
    }
}
//# sourceMappingURL=cxdefaultview.js.map