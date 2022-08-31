class CXList extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
    }
    draw() {
        this._drawBox();
        this._drawList();
    }
    _drawList() {

    }
    setList() {
        
    }
}