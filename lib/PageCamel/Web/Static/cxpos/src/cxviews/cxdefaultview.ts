import { CXBox } from "../cxelements/cxbox.js";
import { CXTable } from "../cxadds/cxtable.js";
export class CXDefaultView extends CXBox {
    private _table: CXTable;

    // attributes for a button with a general function 
    protected _general_func_buttons: {} = {
        radius: 0.1,
        gradient: ['#80b3ffff', '#1193eeff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };
    // attributes for a button with a special function
    protected _special_func_buttons: {} = {
        radius: 0.1,
        gradient: ['#80b3ffff', '#1193eeff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };
    // attributes for a "BAR-Button"
    protected _bar_buttons: {} = {
        radius: 0.1,
        gradient: ['#87de87ff', '#008000ff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._table = new CXTable();
        this.background_color = '#b3b3b3ff';
        this._initialize();
    }
    protected _initialize(): void {
        console.warn("Overwrite the defaultview._initialize function");
    };
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
    protected _draw() {
        super._draw();
        this._elements.forEach(element => {
            element.draw(super._px, super._py, super._pwidth, super._pheight);
        });
    }
    set Table(table: CXTable) {
        this._table = table;
    }
    get Table(): CXTable {
        return this._table;
    }
}