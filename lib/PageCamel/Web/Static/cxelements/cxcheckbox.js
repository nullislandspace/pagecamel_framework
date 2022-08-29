class CXCheckBox extends CXButton {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._box = new CXButton(ctx, 0, 0, 1, 1, true, redraw);
        this._box.font_size = 1.0;
        this._box._text_color = "green";
        this._box._background = "white";
        this._box.text = "";
        this._checked = false;
        this._background = "transparent";
        this.frame_color = "transparent";
        super._text_alignment = "left";
        this._font_size = 1.0;
    }
    _setChecked() {
        this._checked = !this._checked;
        this._box.text = this._checked ? "X" : "";
        this._has_changed = true;
        this._checked ? this.onCheck() : this.onUncheck();
        if(this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    onUncheck = () => {
        // override this function to do something when the checkbox is unchecked
    }
    onCheck = () => {
        // override this function to do something when the checkbox is checked
    }
    _draw() {
        this._box.draw(this._xpixel, this._ypixel, this._heightpixel, this._heightpixel);

        // saving values
        var x = this._xpixel;
        var width = this._widthpixel;

        // changing values
        this._xpixel += this._heightpixel;
        this._widthpixel -= this._heightpixel;
        this._drawTextBox();

        //restoring values
        this._xpixel = x;
        this._widthpixel = width;
    }
    handleEvent(event) {
        var [mouse_x, mouse_y] = this._eventToXY(event);
        super.handleEvent(event);
        if(this._box.checkEvent(event)) {
            console.log("Checked Event");
            this._box.handleEvent(event);
        }
        if(event.type == "mouseup" && this._isInside(mouse_x, mouse_y)) {
            this._setChecked();
        }
    }
}