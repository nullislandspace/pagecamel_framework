import { CXButton } from "./cxbutton.js";
import { CXTextBox } from "./cxtextbox.js";
export class CXCheckBox extends CXButton {
    protected _box: CXTextBox;
    protected _checked: boolean;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean, redraw: boolean) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super._background_color = "transparent";
        super._border_color = "transparent";
        super._text_alignment = "left";
        super._font_size = 1.0;
        super.onClick = () => {
            this._setChecked();
        }
        /** @protected */
        this._box = new CXTextBox(ctx, 0, 0, 1, 1, true, redraw);
        this._box.font_size = 1.0;
        this._box.text_color = "green";
        this._box.background_color = "white";
        this._box.text = "";
        /** @protected */
        this._checked = false;
    }
    /**
     * @protected
     * @description Sets the checked state of the checkbox
     */
    protected _setChecked(): void {
        this._checked = !this._checked;
        this._box.text = this._checked ? "X" : "";
        this._has_changed = true;
        this._checked ? this.onCheck(this) : this.onUncheck(this);
        if (this._redraw) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    /**
     * @public
     * @description Callback function when the checkbox gets unchecked
     */
    public onUncheck = (object: this): void => {
        // override this function to do something when the checkbox is unchecked
    }
    /**
     * @public
     * @description Callback function when the checkbox gets checked
     */
    public onCheck = (object: this): void => {
        // override this function to do something when the checkbox is checked
    }
    /**
     * @protected
     * @description Draws the checkbox
     */
    protected _draw(): void {
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
    protected _handleEvent(event: Event): boolean {
        super.handleEvent(event);
        if (this._box.checkEvent(event)) {
            this._box.handleEvent(event);
        }
        return this._has_changed;
    }
    /**
     * @returns {boolean}
     * @public
    */
    get checked(): boolean {
        return this._checked;
    }
}