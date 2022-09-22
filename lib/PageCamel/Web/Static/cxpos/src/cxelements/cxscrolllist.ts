import { CXBox } from "./cxbox.js";
import { CXScrollBar } from "./cxscrollbar.js";
import { CXTextBox } from "./cxtextbox.js";
export class CXScrollList extends CXBox {
    /** @protected */
    protected _render_list: CXScrollListItem[];
    /** @protected */
    protected _scroll_list_items: CXScrollListItem[];
    /** @protected */
    protected _scroll_list_text: string[][];
    /** @protected */
    protected _item_height: number;
    /** @protected */
    protected _scroll_bar: CXScrollBar;
    /** @protected */
    protected _selected_index: number | null;
    /** @protected */
    protected _display_scrollbar_if_needed: boolean;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
    */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.border_radius = 0.02;
        super.border_width = 0.02;

        this._background_color = 'transparent';
        this._render_list = [];
        this._scroll_list_items = [];
        this._scroll_list_text = [];

        this._item_height = 0.05;

        this._scroll_bar = new CXScrollBar(ctx, 0.95, 0.0, 0.05, 1.0, true, false);

        this._selected_index = null;
        this._setRowsAmount();

        this._display_scrollbar_if_needed = true; // if true, the scrollbar will only be displayed if the list is longer than the height of the scroll list. 


        this._elements.push(this._scroll_bar);
    }
    /**
     * @description sets the amount of rows so that the scrollbar is the correct size
     * @protected 
     */
    protected _setRowsAmount(): void {
        this._scroll_bar.rows = this._scroll_list_items.length;
        this._scroll_bar.rows_per_page = 1 / this._item_height;
    }
    /**
     * @description draws the scroll list
     * @protected
     */
    protected _draw(): void {
        super._draw(); // draws the frame of the parent class
        /* calculates new positions to not overlap with the border */
        var x = this.xpixel + this._border_width_pixel;
        var y = this.ypixel + this._border_width_pixel;
        var w = this.widthpixel - 2 * this._border_width_pixel;
        var h = this.heightpixel - 2 * this._border_width_pixel;
        // gets the current row of the scroll bar
        var scroll_position = this._scroll_bar.scroll_position;
        // get the list of items to be displayed
        this._render_list = this._scroll_list_items.slice(scroll_position, scroll_position + this._scroll_bar.rows_per_page);

        // checks if the scrollbar should be displayed
        if (this._display_scrollbar_if_needed) {
            if (this._scroll_list_items.length > this._scroll_bar.rows_per_page) {
                this._scroll_bar.active = true;
            } else {
                this._scroll_bar.active = false;
            }
        } else {
            this._scroll_bar.active = true;
        }

        // draw the items
        for (let i = 0; i < this._render_list.length; i++) {
            this._render_list[i].ypos = i * this._item_height;

            // changing the width of the scroll list item to fit the width of the scroll list depending if there is a scrollbar or not
            if (this._scroll_bar.active) {
                this._render_list[i].width = 1 - this._scroll_bar.width;
            } else {
                this._render_list[i].width = 1.0;
            }

            this._render_list[i].draw(x, y, w, h);
        }

        this._elements.forEach(element => {
            element.draw(x, y, w, h);
        }
        );
    }
    /**
     * @param {number} index - the index of the selected item
     * @param {this} object - the object of the selected item
     * @public
     */
    onSelect = (object: this, index: number): void => {
        console.log("Selected item " + index);
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    protected _handleEvent(event: Event): boolean {
        var redraw = false;
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this.has_changed = true;
                    redraw = true;
                }
            }
        });
        var index: number | null = null;
        for (let i = 0; i < this._render_list.length; i++) {
            if (this._render_list[i].checkEvent(event)) {
                this._render_list[i].handleEvent(event);
                if (this._render_list[i].has_changed) {
                    this.has_changed = true;
                    redraw = true;
                    index = i;
                    break;
                }
            }
        }
        if (index !== null) {
            index += this._scroll_bar.scroll_position;
            this._selected_index = index;
            this.onSelect(this, index);
            //goes through all the items and sets the selected property to false
            for (let i = 0; i < this._scroll_list_items.length; i++) {
                if (i !== index) {
                    this._scroll_list_items[i].selected = false; // deselect item
                }
            }
        }
        if (redraw && this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
        return this._has_changed;
    }
    /**
     * @param {array} item - the item to be added
     * @description adds an item to the scroll list
     * @example
     * scroll_list.addListItem(["item1", "item2", "item3"]);
     * @public
     */
    addListItem(item: string[]) {
        this._scroll_list_text.push(item);
        var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * this._scroll_list_items.length, 1 - this._scroll_bar.width, this._item_height, true, false);
        list_item.listitem = item;
        list_item.border_radius = 0.1;
        list_item.border_width = 0;
        list_item.background_color = this._background_color;
        this._scroll_list_items.push(list_item);
        this._setRowsAmount();
        if (this._scroll_list_items.length > this._scroll_bar.rows_per_page) {
            //only change the scroll position if the list is longer than the scroll list
            this._scroll_bar.scroll_position = this._scroll_list_items.length - this._scroll_bar.rows_per_page;
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    /**
     * @param {Array} list - Array of strings in the format [[item1, item2, item3], [item4, item5, item6]]
     * @description Sets the list of items to be displayed in the scroll list
     */
    set list(list) {
        this._scroll_list_items = [];
        this._scroll_list_text = list;
        for (let i = 0; i < list.length; i++) {
            var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * i, 1 - this._scroll_bar.width, this._item_height, true, false);
            list_item.listitem = list[i];
            list_item.border_radius = 0.1;
            list_item.background_color = this._background_color;
            list_item.border_width = 0;
            this._scroll_list_items.push(list_item);
            this._setRowsAmount();
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get list() {
        return this._scroll_list_text;
    }

    /**
     * @param {boolean} display - if true, the scrollbar will only be displayed if the list is longer than the height of the scroll list.
     * @description Sets the display of the scrollbar
     * @default true
     */
    set display_scrollbar_if_needed(display: boolean) {
        this._display_scrollbar_if_needed = display;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get display_scrollbar_if_needed() {
        return this._display_scrollbar_if_needed;
    }
    /**
     * @param {number} height - height of the scroll list item
     */
    set item_height(height: number) {
        this._item_height = height;
        this._setRowsAmount();
        for (let i = 0; i < this._scroll_list_items.length; i++) {
            this._scroll_list_items[i].height = height;
            this._scroll_list_items[i].ypos = i * height;
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get item_height(): number {
        return this._item_height;
    }
    /**
     * @param {number} width - width of the scrollbar in pixels
     * @description Sets the width of the scrollbar
     * @default 0.05
     */
    set scroll_bar_width(width: number) {
        this._scroll_bar.width = width;
        this._scroll_bar.xpos = 1 - width;
        for (let i = 0; i < this._scroll_list_items.length; i++) {
            this._scroll_list_items[i].width = 1 - width;
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get scroll_bar_width(): number {
        return this._scroll_bar.width;
    }
    /**
     * @param {String} color - background_color color of the scroll list
     */
    set background_color(color: string) {
        for (let i = 0; i < this._scroll_list_items.length; i++) {
            this._scroll_list_items[i].background_color = color;
        }
        this._background_color = color;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get background_color(): string {
        return this._background_color;
    }
}
class CXScrollListItem extends CXBox {
    protected _textBoxes: CXTextBox[];
    protected _listitem: string[];
    protected _selected: boolean;
    protected _selected_color: string;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._textBoxes = [];
        this._listitem = []; // list of strings
        this._selected = false;
        this._selected_color = "cyan";
        this._background_color = "transparent";
    }
    /**
     * @protected
     */
    protected _draw(): void {
        super._draw();
        for (let i = 0; i < this._textBoxes.length; i++) {
            this._textBoxes[i].draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    protected _handleEvent(event: Event): boolean {
        var [x, y] = this._eventToXY(event as MouseEvent);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                this._selected = true;
                if (this._selected) {
                    this.background_color = this._selected_color;
                }
                redraw = true;
                this._has_changed = true;
        }
        if (redraw && this._redraw) {
            this.draw();
        }
        return this._has_changed;
    }
    /**
     * @param {string[]} list - Array of strings
     */
    set listitem(list: string[]) {
        this._listitem = list;
        this._textBoxes = [];
        var text_box_width = 1 / this._listitem.length;
        for (let i = 0; i < this._listitem.length; i++) {
            var text_box = new CXTextBox(this._ctx, this.xpos + text_box_width * i, this.ypos, text_box_width, 1.0, true, false);
            text_box.background_color = "transparent";
            text_box.border_width = 0;
            text_box.text = this._listitem[i];
            text_box.font_size = 0.8;
            this._textBoxes.push(text_box);
        }
    }
    get listitem() {
        return this._listitem;
    }
    /**
     * @param {number} y
     */
    set ypos(y: number) {
        super._ypos = y;
    }

    get ypos(): number {
        return super._ypos;
    }
    /**
     * @param {boolean} selected
     * @description Sets the selected state of the item
     */
    set selected(selected: boolean) {
        this._selected = selected;
        if (!this._selected) {
            this.background_color = "transparent";
        }
        else {
            this.background_color = this._selected_color;
        }
    }
    /**
     * @returns {boolean}
     * @description Returns the selected state of the item
     */
    get selected(): boolean {
        return this._selected;
    }
    /**
     * @param {string} color
     * @description Sets the color of the item when selected
     */
    set selected_color(color: string) {
        this._selected_color = color;
    }
    get selected_color(): string {
        return this._selected_color;
    }
}