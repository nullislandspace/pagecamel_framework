import { CXBox } from "./cxbox.js";
import { CXTextBox } from "./cxtextbox.js";
export class CXScrollListItem extends CXBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._textBoxes = [];
        this._listitem = [];
        this._selected = false;
        this._selected_color = "cyan";
        this._background_color = "transparent";
        this._name = "CXScrollListItem";
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
