export class CXScrollList extends CXBox {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _background: string;
    _render_list: any[];
    _scroll_list_items: any[];
    _scroll_list_text: any[];
    _item_height: number;
    _scroll_bar: CXScrollBar;
    _selected_index: number;
    _display_scrollbar_if_needed: boolean;
    _setRows(): void;
    onSelect: (i: any) => void;
    handleEvent(event: any): void;
    addListItem(item: any): void;
    /**
     * @param {Array} list - Array of strings in the format [[item1, item2, item3], [item4, item5, item6]]
     * @description Sets the list of items to be displayed in the scroll list
     */
    set list(arg: any[]);
    get list(): any[];
    /**
     * @param {boolean} display - if true, the scrollbar will only be displayed if the list is longer than the height of the scroll list.
     * @description Sets the display of the scrollbar
     * @default true
     */
    set display_scrollbar_if_needed(arg: boolean);
    get display_scrollbar_if_needed(): boolean;
    /**
     * @param {number} height - height of the scroll list item
     */
    set item_height(arg: number);
    get item_height(): number;
    /**
     * @param {number} width - width of the scrollbar in pixels
     * @description Sets the width of the scrollbar
     * @default 0.05
     */
    set scroll_bar_width(arg: number);
    get scroll_bar_width(): number;
    /**
     * @param {String} value - background color of the scroll list
     */
    set background(arg: string);
    get background(): string;
}
import { CXBox } from "./cxbox.js";
import { CXScrollBar } from "./cxscrollbar.js";
