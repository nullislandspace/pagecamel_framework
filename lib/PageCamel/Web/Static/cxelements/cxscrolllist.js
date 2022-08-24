class CXScrollList extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.radius = 10;
        this._render_list = [];
        this._scroll_list_items = [];
        this._scroll_list_text = [];

        this._item_height = 0.05;

        this._scroll_bar = new CXScrollBar(ctx, 0.95, 0.0, 0.05, 1.0, true, false);
        this._scroll_bar.scrollbar.radius = 5;
        this._scroll_bar.radius = 5;

        this._selected_index = null;
        this._setRows();
        this.border_width = 2;

        this._display_scrollbar_if_needed = true; // if true, the scrollbar will only be displayed if the list is longer than the height of the scroll list. 

        this._elements.push(this._scroll_bar);
    }
    _setRows() {
        this._scroll_bar.rows = this._scroll_list_items.length;
        this._scroll_bar.rows_per_page = 1 / this._item_height;
    }
    _draw() {
        super._draw(); // draws the frame of the parent class
        /* calculates new positions to not overlap with the border */
        var x = this.xpixel + this._border_width;
        var y = this.ypixel + this._border_width;
        var w = this.widthpixel - 2 * this._border_width;
        var h = this.heightpixel - 2 * this._border_width;
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
                this._render_list[i].width = 0.95;
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
    onSelect = (i) => {
        console.log("Selected item " + i);
    }
    handleEvent(event) {
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
        var index = null;
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
            this.onSelect(index);
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
    }
    addListItem(item) {
        this._scroll_list_text.push(item);
        var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * this._scroll_list_items.length, 0.95, this._item_height, true, false);
        list_item.listitem = item;
        list_item.radius = 5;
        list_item.border_width = 0;
        this._scroll_list_items.push(list_item);
        this._setRows();
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
            var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * i, 0.95, this._item_height, true, false);
            list_item.listitem = list[i];
            list_item.radius = 5;
            list_item.border_width = 0;
            this._scroll_list_items.push(list_item);
            this._setRows();
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
    set display_scrollbar_if_needed(display) {
        this._display_scrollbar_if_needed = display;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    /**
     * @param {number} height - height of the scroll list item
     */
    set item_height(height) {
        this._item_height = height;
        this._setRows();
        for (let i = 0; i < this._scroll_list_items.length; i++) {
            this._scroll_list_items[i].height = height;
            this._scroll_list_items[i].ypos = i * height;
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get item_height() {
        return this._item_height;
    }
}