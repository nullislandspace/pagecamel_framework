class CXDropDown extends CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.text_alignment = "left";
        super.box_color = "transparent";

        this._elements = [];
        this._field_width = 0.8;
        this._field_height = 0.2;
        this._dropdown_button = new CXButton(ctx, 0, 0, this._field_width - 0.2, this._field_height, true, false);
        this._dropdown_arrow = new CXArrowButton(ctx, this._field_width - 0.2, 0, 0.2, this._field_height, true, false);
        this._dropdown_list = new CXScrollList(ctx, 0, this._field_height, 1.0, 1.0 - this._field_height, true, false);

        this._dropdown_button.text_alignment = "center";
        this._dropdown_button.box_color = "transparent";

        this._dropdown_list.radius = 0;
        this._dropdown_list.item_height = 0.2 * 0.8;
        this._dropdown_list.allow_deselect = false;

        this._dropdown_arrow.box_color = "transparent";
        this._dropdown_arrow.arrow_color = "black";
        this._dropdown_arrow.arrow_direction = "down";
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
    _draw() {
        super._draw();
        this._dropdown_arrow.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_button.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_list.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    _openDropDown() {
        console.log("open");
        this._opened = true;
        this._dropdown_list.active = true;
        console.log('Is active?', this._dropdown_list.active);
    }
    _closeDropDown() {
        console.log("close");
        this._opened = false;
        this._dropdown_list.active = false;
        console.log('Is active?', this._dropdown_list.active);
    }
    handleEvent(event) {
        console.log('Is active?', this._dropdown_list.active);
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
    /**
     * @param {string} value - text to be displayed in the field
     */
    set text(value) {
        this._dropdown_button.text = value;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
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
}