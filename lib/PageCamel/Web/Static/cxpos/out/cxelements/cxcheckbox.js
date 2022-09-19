import { CXButton } from "./cxbutton.js";
import { CXTextBox } from "./cxtextbox.js";
export class CXCheckBox extends CXButton {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.onUncheck = () => {
        };
        this.onCheck = () => {
        };
        super._background_color = "transparent";
        super._border_color = "transparent";
        super._text_alignment = "left";
        super._font_size = 1.0;
        super.onClick = () => {
            this._setChecked();
        };
        this._box = new CXTextBox(ctx, 0, 0, 1, 1, true, redraw);
        this._box.font_size = 1.0;
        this._box.text_color = "green";
        this._box.background_color = "white";
        this._box.text = "";
        this._checked = false;
    }
    _setChecked() {
        this._checked = !this._checked;
        this._box.text = this._checked ? "X" : "";
        this._has_changed = true;
        this._checked ? this.onCheck() : this.onUncheck();
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    _draw() {
        this._box.draw(this._xpixel, this._ypixel, this._heightpixel, this._heightpixel);
        var x = this._xpixel;
        var width = this._widthpixel;
        this._xpixel += this._heightpixel;
        this._widthpixel -= this._heightpixel;
        this._drawTextBox();
        this._xpixel = x;
        this._widthpixel = width;
    }
    _handleEvent(event) {
        super.handleEvent(event);
        if (this._box.checkEvent(event)) {
            this._box.handleEvent(event);
        }
        return this._has_changed;
    }
    get checked() {
        return this._checked;
    }
}
