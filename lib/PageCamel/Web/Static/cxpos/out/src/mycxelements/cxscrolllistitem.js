import { CXBox } from "./cxbox.js";
import { CXTextBox } from "./cxtextbox.js";
export class CXScrollListItem extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._textBoxes = [];
        this._listitem = []; // list of strings
        this._selected = false;
        this._selected_color = "cyan";
        this._background = "transparent";
    }
    _draw() {
        super._draw();
        for (let i = 0; i < this._textBoxes.length; i++) {
            this._textBoxes[i].draw(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        }
    }
    /**
     * @param {event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    handleEvent(event) {
        var [x, y] = this._eventToXY(event);
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                this._selected = true;
                if (this._selected) {
                    this.background = this._selected_color;
                }
                redraw = true;
                this._has_changed = true;
        }
        if (redraw && this._redraw) {
            this.draw();
        }
    }
    /**
     * @param {Array} list - Array of strings
     */
    set listitem(list) {
        this._listitem = list;
        this._textBoxes = [];
        var text_box_width = 1 / this._listitem.length;
        for (let i = 0; i < this._listitem.length; i++) {
            var text_box = new CXTextBox(this._ctx, this.xpos + text_box_width * i, this.ypos, text_box_width, 1.0, true, false);
            text_box.background = "transparent";
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
    set ypos(y) {
        super._ypos = y;
    }
    /**
     * @param {boolean} selected
     * @description Sets the selected state of the item
     */
    set selected(selected) {
        this._selected = selected;
        if (!this._selected) {
            this.background = "transparent";
        }
        else {
            this.background = this._selected_color;
        }
    }
    /**
     * @returns {boolean}
     * @description Returns the selected state of the item
     */
    get selected() {
        return this._selected;
    }
    /**
     * @param {string} color
     * @description Sets the color of the item when selected
     */
    set selected_color(color) {
        this._selected_color = color;
    }
    get selected_color() {
        return this._selected_color;
    }
}
