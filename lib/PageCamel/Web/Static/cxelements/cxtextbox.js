class CXTextBox extends CXBox {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.text_color = "black";
        this.font_family = "Arial";
        this.font_size = "12";
        this.text = "";
        this.text_alignment = "center";
    }
    _drawText() {
        this.ctx.fillStyle = this.text_color;
        this.ctx.font = this.font_size + "px " + this.text_font;

        var text_metrics = ctx.measureText(this.text); // get the metrics of the text
        var actualHeight = text_metrics.actualBoundingBoxAscent + text_metrics.actualBoundingBoxDescent; // get the actual height of the text

        var text_x;
        if (this.text_alignment == "center") {
            text_x = this.xpos + this.width / 2 - text_metrics.width / 2;
        }
        else if (this.text_alignment == "left") {
            text_x = this.xpos;
        }
        else if (this.text_alignment == "right") {
            text_x = this.xpos + this.width - text_metrics.width;
        }
        this.ctx.fillText(this.text, text_x, this.ypos + this.height / 2 - actualHeight / 2 + text_metrics.actualBoundingBoxAscent);

    }
    _drawTextBox() {
        this._drawBox();
        this._drawText();
    }
    draw () {
        this._drawTextBox();
    }
}