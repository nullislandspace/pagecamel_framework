class CXTextBox extends CXBox {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._text_color = "black";
        this._font_family = "Arial";
        this._font_size = "15";
        this._text = "";
        this._text_alignment = "center";
        this._auto_line_break = true;
    }
    _drawText() {
        this._ctx.fillStyle = this._text_color;
        this._ctx.font = this._font_size + "px " + this._font_family;
        this._ctx.textAlign = 'start';

        if (this._text) {
            var text_array = [];
            if (!Array.isArray(this._text)) { // check if it's an array
                text_array = [this._text];
            }
            else {
                text_array = this._text;
            }
            var new_displaytext = [];
            var text_lines_height = 0;
            if (this._auto_line_break) {
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
                if (this._text_alignment == "center") {
                    text_x = this.xpixel + this.widthpixel / 2 - text_metrics.width / 2;
                }
                else if (this._text_alignment == "left") {
                    text_x = this.xpixel;
                }
                else if (this._text_alignment == "right") {
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
    /**
     * @param {string} color - Color of the text
     * @default "black"
     */
    set text_color(color) {
        this._text_color = color;
    }
    get text_color() {
        return this._text_color;
    }
    /**
     * @param {string} font_family - Font family of the text
     * @default "Arial"
     */
    set font_family(font_family) {
        this._font_family = font_family;
    }
    get font_family() {
        return this._font_family;
    }
    /**
     * @param {string} font_size - Font size of the text
     * @description Font size is in em
     * @default "15"
     */
    set font_size(font_size) {
        
        this._font_size = font_size;
    }
    get font_size() {
        return this._font_size;
    }
    /**
     * @param {string} text - Text to be displayed
     * @description If the text is an array, each element will be displayed on a new line
     * @default ""
     */
    set text(text) {
        this._text = text;
    }
    get text() {
        return this._text;
    }
    /**
     * @param {string} text_alignment - Text alignment
     * @description Possible values are "left", "center" and "right"
     * @default "center"
     */
    set text_alignment(text_alignment) {
        this._text_alignment = text_alignment;
    }
    get text_alignment() {
        return this._text_alignment;
    }
    /**
     * @param {boolean} auto_line_break - Auto line break
     * @description If true, the text will be automatically line broken
     * @default true
     */
    set auto_line_break(auto_line_break) {
        this._auto_line_break = auto_line_break;
    }
}