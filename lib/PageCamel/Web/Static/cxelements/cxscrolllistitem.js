class CXScrollListItem extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
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
    }
}