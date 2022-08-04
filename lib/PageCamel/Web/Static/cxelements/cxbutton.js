class CXButton extends CXTextBox {
    constructor(ctx) {
        super(ctx);
    }
    drawButton(x, y, width, height) {
        this.drawTextBox(x, y, width, height);
    }
}