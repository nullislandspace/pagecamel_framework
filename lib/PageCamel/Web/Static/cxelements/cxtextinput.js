class CXTextInput extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
    }
    _drawTextInput() {
        //draw the text input
    }
    _draw() {
        this._drawTextInput();
    }

}