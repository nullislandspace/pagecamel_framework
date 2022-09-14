export class CXScrollListItem extends CXBox {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _textBoxes: any[];
    _listitem: any[];
    _selected: boolean;
    _selected_color: string;
    _background: string;
    background: string;
    /**
     * @param {Array} list - Array of strings
     */
    set listitem(arg: any[]);
    get listitem(): any[];
    /**
     * @param {boolean} selected
     * @description Sets the selected state of the item
     */
    set selected(arg: boolean);
    /**
     * @returns {boolean}
     * @description Returns the selected state of the item
     */
    get selected(): boolean;
    /**
     * @param {string} color
     * @description Sets the color of the item when selected
     */
    set selected_color(arg: string);
    get selected_color(): string;
}
import { CXBox } from "./cxbox.js";
