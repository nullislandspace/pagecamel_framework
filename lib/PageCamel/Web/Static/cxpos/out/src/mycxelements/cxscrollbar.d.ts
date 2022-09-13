export class CXScrollBar extends CXBox {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    scrollbar: CXBox;
    _rows: number;
    _rows_per_page: number;
    scroll_position: number;
    pixels_per_row: number;
    _scrollbar_pressed: boolean;
    _drawScrollbar(): void;
    _getScrollbarYPos(): number;
    _getScrollbarHeight(): number;
    _scrollbarPressed(event: any): void;
    mouse_down_scrollbar_ypos: number;
    handleEvent(event: any): void;
    prev_scroll_position: number;
    /**
     * @param {number} rows
     */
    set rows(arg: number);
    get rows(): number;
    /**
     * @param {number} rows_per_page
     */
    set rows_per_page(arg: number);
    get rows_per_page(): number;
}
import { CXBox } from "./cxbox.js";
