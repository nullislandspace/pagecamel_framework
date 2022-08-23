class CXDropDown extends CXDefault {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.text_alignment = "left";
        super.box_color = "transparent";

        this._field_width = 0.8;
        this._field_height = 0.2;
        this._dropdown_button = new CXButton(ctx, 0, 0, this._field_width , this._field_height, true, false);        
        this._dropdown_arrow = new CXArrowButton(ctx, this._field_width - 0.2, 0, 0.2, this._field_height, true, false);
        this._dropdown_list = new CXScrollList(ctx, 0, this._field_height, 1.0, 1.0 - this._field_height, true, false);

        this._dropdown_list.radius = 0;
        this._dropdown_button.box_color = "transparent";

        this._dropdown_arrow.box_color = "transparent";
        this._dropdown_arrow.arrow_color = "black";
        this._dropdown_arrow.arrow_direction = "down";
        this._opened = false;

        this._dropdown_button.onClick = () => {
            if(this._opened) {
                this._closeDropDown();
            } else {
                this._openDropDown();
            }
        }
    }
    _draw() {
        super._draw();
        this._dropdown_arrow.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_button.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        if (this._opened) {
            this._dropdown_list.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        }
    }
    _openDropDown() {
        console.log("open");
        this._opened = true;
    }
    _closeDropDown() {
        console.log("close");
        this._opened = false;
    }
    handleEvent(event) {
        var redraw = false;
        switch (event.type) {
            case "mousedown":
                if (this._opened) {
                    this._closeDropDown();
                }
                else {
                    this._openDropDown();
                }
                redraw = true;
        }
        if (redraw && this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    /**
     * @param {number} value - width of the field in percent of the dropdown width
     */
    set field_width(value) {
        this._field_width = value;
        this._dropdown_button.width = value;
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
    set text(value) {
        this._dropdown_button.text = value;
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
}