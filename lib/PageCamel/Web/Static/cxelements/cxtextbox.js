class CXTextBox extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
        this.text_color = "black";
        this.font_family = "Arial";
        this.font_size = "1";
        this.text = "";
        this.text_alignment = "center";
        this.auto_line_break = true;
    }
    _drawText() {
        this._ctx.fillStyle = this.text_color;
        this._ctx.font = this.font_size + "em " + this.text_font;
        this._ctx.textAlign = 'start';

        if (this.text) {
            var text_array = [];
            if (!Array.isArray(this.text)) { // check if it's an array
                text_array = [this.text];
            }
            else {
                text_array = this.text;
            }
            var new_displaytext = [];
            var text_lines_height = 0;
            if (this.auto_line_break) {
                for (var j in text_array) {
                    var new_lines = [];
                    if (this.border_width > 0) {
                        new_lines = autoLineBreak(this._ctx, text_array[j], this.widthpixel - this.border_width * 2);
                    } else {
                        new_lines = autoLineBreak(this._ctx, text_array[j], this.widthpixel);
                    }
                    if (new_lines.length > 0) {
                        new_displaytext = [...new_displaytext, ...new_lines];
                        for (var k = 0; k < new_lines.length; k++) {
                            var text_metrics = this._ctx.measureText(new_lines[k]); // get the text metrics for each line
                            var actualHeight = text_metrics.actualBoundingBoxAscent + text_metrics.actualBoundingBoxDescent; // get the actual height of the text
                            text_lines_height += actualHeight;
                        }
                    }
                }
            } else {
                var text_metrics = this._ctx.measureText(text_array[0]); // get the text metrics for each line
                var actualHeight = text_metrics.actualBoundingBoxAscent + text_metrics.actualBoundingBoxDescent; // get the actual height of the text
                text_lines_height += actualHeight;
                new_displaytext = text_array;
            }
            var line_height = text_lines_height / new_displaytext.length; // get the average line height
            var yoffs = 0;
            var start_y = this.ypixel + this.heightpixel / 2 - (text_lines_height - 1.8 * line_height) / 2; // get the starting y position
            for (j = 0; j < new_displaytext.length; j++) {
                var text_line = new_displaytext[j];
                var text_metrics = this._ctx.measureText(text_line); // get the metrics of the text
                var actualHeight = text_metrics.actualBoundingBoxAscent + text_metrics.actualBoundingBoxDescent; // get the actual height of the text
                var text_x;
                if (this.text_alignment == "center") {
                    text_x = this.xpixel + this.widthpixel / 2 - text_metrics.width / 2;
                }
                else if (this.text_alignment == "left") {
                    text_x = this.xpixel;
                }
                else if (this.text_alignment == "right") {
                    text_x = this.xpixel + this.widthpixel - text_metrics.width;
                }
                this._ctx.fillText(text_line, text_x, start_y + yoffs); // draw the text
                yoffs = yoffs + line_height;
            }
            //draw rectangle around text
            this._ctx.strokeStyle = "black";
            this._ctx.lineWidth = 1;
            //this._ctx.strokeRect(this.xpixel + 10, start_y, this.widthpixel - 20, yoffs);
        }
    }
    _drawTextBox() {
        super._draw();
        this._drawText();
    }
    _draw() {
        this._drawTextBox();
    }
}