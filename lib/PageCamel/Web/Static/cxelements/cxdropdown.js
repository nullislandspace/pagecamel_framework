//import {CXTextBox} from "./cxtextbox.js";
/*export*/ class CXDropDown extends CXTextBox {
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx, x, y, width, height, name="", is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, name, is_relative, redraw);
        super.text_alignment = "left";
        super.background_color = "transparent";

        /** @protected */
        this._elements = [];
        /** @protected */
        this._field_width = 0.8;
        /** @protected */
        this._field_height = 0.2;
        /** @protected */
        this._dropdown_button = new CXButton(ctx, 0, 0, this._field_width - 0.2, this._field_height, true, false);
        /** @protected */
        this._dropdown_arrow = new CXArrowButton(ctx, this._field_width - 0.2, 0, 0.2, this._field_height, true, false);
        /** @protected */
        this._dropdown_list = new CXScrollList(ctx, 0, this._field_height, 1.0, 1.0 - this._field_height, true, false);

        this._dropdown_button.text_alignment = "center";
        this._dropdown_button.background_color = "transparent";

        this._dropdown_list.radius = 0;
        this._dropdown_list.item_height = 0.2 * 0.8;
        this._dropdown_list.allow_deselect = false;
        this._dropdown_list.active = false;
        this._dropdown_list.scroll_bar_width = 0.1;

        this._dropdown_arrow.background_color = "transparent";
        this._dropdown_arrow.arrow_color = "black";
        this._dropdown_arrow.arrow_direction = "down";
        /**@protected */
        this._opened = false;

        this._elements.push(this._dropdown_button);
        this._elements.push(this._dropdown_arrow);
        this._elements.push(this._dropdown_list);

        //defines what happens when the dropdown button is clicked on
        this.onClick = () => {
            console.log('Clicked on dropdown button');
            if (this._opened) {
                this._closeDropDown();
            } else {
                this._openDropDown();
            }
            this._dropdown_button.has_changed = true;
            this._dropdown_arrow.has_changed = true;
            if (this._redraw) {
                this.draw(this._px, this._py, this._pwidth, this._pheight);
            }
        }
        this._dropdown_arrow.onClick = this.onClick;
        this._dropdown_button.onClick = this.onClick;

        this._dropdown_list.onSelect = (index) => {
            console.log('Selected', index);
            this._dropdown_button.text = this._dropdown_list.list[index][0];
            //this._dropdown_button.text = this._dropdown_list.list[index].text;
            this._closeDropDown();
        }
    }
    /**
     * @protected
     */
    _draw() {
        this._dropdown_arrow.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_button.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_list.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    /**
     * @protected
     */
    _openDropDown() {
        console.log("open");
        this._opened = true;
        this._dropdown_list.active = true;
    }
    /**
     * @protected
     */
    _closeDropDown() {
        console.log("close");
        this._opened = false;
        this._dropdown_list.active = false;
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    handleEvent(event) {
        var redraw = false;
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this._has_changed = true;
                    redraw = true;
                }
            }
        });
        if (redraw && this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    /**
     * @param {number} value - width of the field in percent of the dropdown width
     */
    set field_width(value) {
        this._field_width = value;
        this._dropdown_button.width = value - 0.2;
        this._dropdown_arrow.xpos = value - 0.2;
        this._dropdown_arrow.width = 0.2;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get field_width() {
        return this._field_width;
    }
    /**
     * @param {number} value - height of the field in percent of the dropdown height
     */
    set field_height(value) {
        this._field_height = value;
        this._dropdown_button.height = value;
        this._dropdown_arrow.height = value;
        this._dropdown_list.ypos = value;
        this._dropdown_list.height = 1.0 - value;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get field_height() {
        return this._field_height;
    }
    /**
     * @param {string} value - text to be displayed in the field
     */
    set text(value) {
        this._dropdown_button.text = value;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get text() {
        return this._dropdown_button.text;
    }

    /**
     * @param {Array} string_array - 2D array of strings to be displayed in the dropdown list
     */
    set list(string_array) {
        this._dropdown_list.list = string_array;

        //sets the height of the list items to 80% of the field height
        this._dropdown_list.item_height = this._field_height * 0.8;
        console.log('New item height: ' + this._dropdown_list.item_height);
        //sets the height of the list to the height of the items or the height of the dropdown - the field height
        this._dropdown_list.height = Math.min(this._dropdown_list.item_height * string_array.length, 1.0 - this._field_height);
        console.log('New Height:', this._dropdown_list.height);
        //sets the height of the dropdown to the height of the field + the height of the list
        this._dropdown_list.item_height = (this._field_height / this._dropdown_list.height) * 0.8;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get list() {
        return this._dropdown_list.list;
    }
    /**
     * @param {String} value - background_color color of the field
     */
    set background_color(value) {
        this._dropdown_button.background_color = value;
        this._dropdown_arrow.background_color = value;
        this._dropdown_list.background_color = value;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    get background_color() {
        return this._dropdown_button.background_color;
    }
}