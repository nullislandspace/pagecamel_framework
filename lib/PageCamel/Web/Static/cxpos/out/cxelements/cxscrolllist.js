import { CXBox } from "./cxbox.js";
import { CXScrollBar } from "./cxscrollbar.js";
import { CXTextBox } from "./cxtextbox.js";
export class CXScrollList extends CXBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.onSelect = (object, index) => {
            console.log("Selected item " + index);
        };
        super.radius = 0.02;
        super.border_width = 0.02;
        this._background_color = 'transparent';
        this._render_list = [];
        this._scroll_list_items = [];
        this._scroll_list_text = [];
        this._item_height = 0.05;
        this._scroll_bar = new CXScrollBar(ctx, 0.95, 0.0, 0.05, 1.0, true, false);
        this._selected_index = null;
        this._setRowsAmount();
        this._display_scrollbar_if_needed = true;
        this._elements.push(this._scroll_bar);
    }
    _setRowsAmount() {
        this._scroll_bar.rows = this._scroll_list_items.length;
        this._scroll_bar.rows_per_page = 1 / this._item_height;
    }
    _draw() {
        super._draw();
        var x = this.xpixel + this._border_width_pixel;
        var y = this.ypixel + this._border_width_pixel;
        var w = this.widthpixel - 2 * this._border_width_pixel;
        var h = this.heightpixel - 2 * this._border_width_pixel;
        var scroll_position = this._scroll_bar.scroll_position;
        this._render_list = this._scroll_list_items.slice(scroll_position, scroll_position + this._scroll_bar.rows_per_page);
        if (this._display_scrollbar_if_needed) {
            if (this._scroll_list_items.length > this._scroll_bar.rows_per_page) {
                this._scroll_bar.active = true;
            }
            else {
                this._scroll_bar.active = false;
            }
        }
        else {
            this._scroll_bar.active = true;
        }
        for (let i = 0; i < this._render_list.length; i++) {
            this._render_list[i].ypos = i * this._item_height;
            if (this._scroll_bar.active) {
                this._render_list[i].width = 1 - this._scroll_bar.width;
            }
            else {
                this._render_list[i].width = 1.0;
            }
            this._render_list[i].draw(x, y, w, h);
        }
        this._elements.forEach(element => {
            element.draw(x, y, w, h);
        });
    }
    _handleEvent(event) {
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
            this.onSelect(this, index);
            for (let i = 0; i < this._scroll_list_items.length; i++) {
                if (i !== index) {
                    this._scroll_list_items[i].selected = false;
                }
            }
        }
        if (redraw && this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
        return this._has_changed;
    }
    addListItem(item) {
        this._scroll_list_text.push(item);
        var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * this._scroll_list_items.length, 1 - this._scroll_bar.width, this._item_height, true, false);
        list_item.listitem = item;
        list_item.radius = 0.1;
        list_item.border_width = 0;
        list_item.background_color = this._background_color;
        this._scroll_list_items.push(list_item);
        this._setRowsAmount();
        if (this._scroll_list_items.length > this._scroll_bar.rows_per_page) {
            this._scroll_bar.scroll_position = this._scroll_list_items.length - this._scroll_bar.rows_per_page;
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    set list(list) {
        this._scroll_list_items = [];
        this._scroll_list_text = list;
        for (let i = 0; i < list.length; i++) {
            var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * i, 1 - this._scroll_bar.width, this._item_height, true, false);
            list_item.listitem = list[i];
            list_item.radius = 0.1;
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
    set display_scrollbar_if_needed(display) {
        this._display_scrollbar_if_needed = display;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get display_scrollbar_if_needed() {
        return this._display_scrollbar_if_needed;
    }
    set item_height(height) {
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
    get item_height() {
        return this._item_height;
    }
    set scroll_bar_width(width) {
        this._scroll_bar.width = width;
        this._scroll_bar.xpos = 1 - width;
        for (let i = 0; i < this._scroll_list_items.length; i++) {
            this._scroll_list_items[i].width = 1 - width;
        }
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get scroll_bar_width() {
        return this._scroll_bar.width;
    }
    set background_color(color) {
        for (let i = 0; i < this._scroll_list_items.length; i++) {
            this._scroll_list_items[i].background_color = color;
        }
        this._background_color = color;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get background_color() {
        return this._background_color;
    }
}
class CXScrollListItem extends CXBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._textBoxes = [];
        this._listitem = [];
        this._selected = false;
        this._selected_color = "cyan";
        this._background_color = "transparent";
    }
    _draw() {
        super._draw();
        for (let i = 0; i < this._textBoxes.length; i++) {
            this._textBoxes[i].draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
    }
    _handleEvent(event) {
        var [x, y] = this._eventToXY(event);
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
    set listitem(list) {
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
    set ypos(y) {
        super._ypos = y;
    }
    get ypos() {
        return super._ypos;
    }
    set selected(selected) {
        this._selected = selected;
        if (!this._selected) {
            this.background_color = "transparent";
        }
        else {
            this.background_color = this._selected_color;
        }
    }
    get selected() {
        return this._selected;
    }
    set selected_color(color) {
        this._selected_color = color;
    }
    get selected_color() {
        return this._selected_color;
    }
}
//# sourceMappingURL=cxscrolllist.js.map