import { CXTextBox } from "./cxtextbox.js";
import { CXArrowButton } from "./cxarrowbutton.js";
import { CXButton } from "./cxbutton.js";
import { CXScrollList } from "./cxscrolllist.js";
export class CXDropDown extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.text_alignment = "left";
        super.background_color = "transparent";
        this._elements = [];
        this._field_width = 0.8;
        this._field_height = 0.2;
        this._dropdown_button = new CXButton(ctx, 0, 0, this._field_width - 0.2, this._field_height, true, false);
        this._dropdown_arrow = new CXArrowButton(ctx, this._field_width - 0.2, 0, 0.2, this._field_height, true, false);
        this._dropdown_list = new CXScrollList(ctx, 0, this._field_height, 1.0, 1.0 - this._field_height, true, false);
        this._dropdown_button.text_alignment = "center";
        this._dropdown_button.background_color = "transparent";
        this._dropdown_list.radius = 0;
        this._dropdown_list.item_height = 0.2 * 0.8;
        this._dropdown_list.active = false;
        this._dropdown_list.scroll_bar_width = 0.1;
        this._dropdown_arrow.background_color = "transparent";
        this._dropdown_arrow.arrow_color = "black";
        this._dropdown_arrow.arrow_direction = "down";
        this._opened = false;
        this._elements.push(this._dropdown_button);
        this._elements.push(this._dropdown_arrow);
        this._elements.push(this._dropdown_list);
        this._onClick = () => {
            console.log('Clicked on dropdown button');
            if (this._opened) {
                this._closeDropDown();
            }
            else {
                this._openDropDown();
            }
            this._dropdown_button.has_changed = true;
            this._dropdown_arrow.has_changed = true;
            this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        };
        this._dropdown_arrow.onClick = this._onClick;
        this._dropdown_button.onClick = this._onClick;
        this._dropdown_list.onSelect = (object, index) => {
            if (this._dropdown_list.active) {
                console.log('Selected', index);
                this._dropdown_button.text = this._dropdown_list.list[index][0];
                this._closeDropDown();
                this._has_changed = true;
                this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
            }
        };
    }
    _draw() {
        this._dropdown_arrow.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_button.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_list.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    _openDropDown() {
        console.log("open");
        this._opened = true;
        this._dropdown_list.active = true;
    }
    _closeDropDown() {
        console.log("close");
        this._dropdown_list.active = false;
        this._opened = false;
    }
    _handleEvent(event) {
        console.log("handle event");
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this._has_changed = true;
                }
            }
        });
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        return this._has_changed;
    }
    set field_width(width) {
        this._field_width = width;
        this._dropdown_button.width = width - 0.2;
        this._dropdown_arrow.xpos = width - 0.2;
        this._dropdown_arrow.width = 0.2;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get field_width() {
        return this._field_width;
    }
    set field_height(value) {
        this._field_height = value;
        this._dropdown_button.height = value;
        this._dropdown_arrow.height = value;
        this._dropdown_list.ypos = value;
        this._dropdown_list.height = 1.0 - value;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get field_height() {
        return this._field_height;
    }
    set text(value) {
        this._dropdown_button.text = value;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get text() {
        return this._dropdown_button.text;
    }
    set list(string_array) {
        this._dropdown_list.list = string_array;
        this._dropdown_list.item_height = this._field_height * 0.8;
        console.log('New item height: ' + this._dropdown_list.item_height);
        this._dropdown_list.height = Math.min(this._dropdown_list.item_height * string_array.length, 1.0 - this._field_height);
        console.log('New Height:', this._dropdown_list.height);
        this._dropdown_list.item_height = (this._field_height / this._dropdown_list.height) * 0.8;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get list() {
        return this._dropdown_list.list;
    }
    set background_color(color) {
        this._dropdown_button.background_color = color;
        this._dropdown_arrow.background_color = color;
        this._dropdown_list.background_color = color;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get background_color() {
        return this._dropdown_button.background_color;
    }
}
//# sourceMappingURL=cxdropdown.js.map