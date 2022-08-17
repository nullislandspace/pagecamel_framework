class CXScrollListItem extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._textBoxes = [];
        this._listitem = []; // list of strings
    }
    _draw() {
        super._draw();
    }
    /**
     * @param {Array} list - Array of strings
     */
    set listitem(list) {
        this._listitem = list;
        this._textBoxes = [];
        for (let i = 0; i < this._listitem.length; i++) {
            this._textBoxes.push(new CXTextBox(this._ctx, 0, 0, this._width, this._height, this._listitem[i], true, false));
        }
    }
}