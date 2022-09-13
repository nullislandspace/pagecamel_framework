import { CXButton } from "./cxbutton.js";
export class CXCheckBox extends CXButton {
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super._background_color = "transparent";
        super._border_color = "transparent";
        super._text_alignment = "left";
        super._font_size = 1.0;
        super.onClick = () => {
            this._setChecked(!this.isChecked);
        }
        /** @protected */
        this._box = new CXTextBox(ctx, 0, 0, 1, 1, true, redraw);
        this._box.font_size = 1.0;
        this._box._text_color = "green";
        this._box._background_color = "white";
        this._box.text = "";
        /** @protected */
        this._checked = false;
        /** @protected */
        this._name = "CXCheckBox";
    }
    /**
     * @protected
     * @description Sets the checked state of the checkbox
     */
    _setChecked() {
        this._checked = !this._checked;
        this._box.text = this._checked ? "X" : "";
        this._has_changed = true;
        this._checked ? this.onCheck() : this.onUncheck();
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    /**
     * @public
     * @description Callback function when the checkbox gets unchecked
     */
    onUncheck = () => {
        // override this function to do something when the checkbox is unchecked
    }
    /**
     * @public
     * @description Callback function when the checkbox gets checked
     */
    onCheck = () => {
        // override this function to do something when the checkbox is checked
    }
    /**
     * @protected
     * @description Draws the checkbox
     */
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
    /**
     * @public
     * @description handles the event
     */
    handleEvent(event) {
        super.handleEvent(event);
        if (this._box.checkEvent(event)) {
            this._box.handleEvent(event);
        }
    }
    /**
     * @returns {boolean}
     * @public
    */
    get checked() {
        return this._checked;
    }
}