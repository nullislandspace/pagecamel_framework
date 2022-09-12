//import { CXBox } from "./cxbox";
/*export*/ class CXTextBox extends CXBox {
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {string} name - the name of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx, x, y, width, height, name="", is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, name, is_relative, redraw);
        /** @protected */
        this._text_color = "black";
        /** @protected */
        this._font_family = "Arial";
        /** @protected  */
        this._font_size_pixel = 0;
        /** @protected  */
        this._font_size = 0;
        if (is_relative) {
            this._font_size = 0.5;
        } else {
            this._font_size = 12;
        }
        /** @protected */
        this._text = "";
        /** @protected */
        this._text_alignment = "center";
        /** @protected */
        this._auto_line_break = true;

        /** @protected */
        this._font_size_pixel = 0;
    }
    /**
     * @description converts the font size to pixel size
     * @protected
     */
    _convertFontSizeToPixel() {
        this._font_size_pixel = this._calcRelYToPixel(this._font_size, this._heightpixel);
    }
    /** 
     * @protected   
     * @description Converts the relative position to pixel position
    */
    _convertToPixel() {
        this._convertFrameToPixel();
        this._convertFontSizeToPixel();
    }
    /**
     * @protected
     */
    _drawText() {
        this._ctx.fillStyle = this._text_color;
        this._ctx.font = this._font_size_pixel + "px " + this._font_family;
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
                        new_lines = this._autoLineBreak(text_array[j], this.widthpixel - this.border_width * 2);
                    } else {
                        new_lines = this._autoLineBreak(text_array[j], this.widthpixel);
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
                if (new_displaytext.length == 1) {
                    start_y = this.ypixel + (this.heightpixel / 2 - actualHeight / 2) + actualHeight;
                }
                var text_x;
                if (this._text_alignment == "center") {
                    text_x = this.xpixel + this.widthpixel / 2 - text_metrics.width / 2;
                }
                else if (this._text_alignment == "left") {
                    text_x = this.xpixel + 8;
                }
                else if (this._text_alignment == "right") {
                    text_x = this.xpixel + this.widthpixel - text_metrics.width;
                }
                this._ctx.fillText(text_line, text_x, start_y + yoffs, this.widthpixel); // draw the text
                yoffs = yoffs + line_height;
            }
            //draw rectangle around text
            this._ctx.strokeStyle = "black";
            this._ctx.lineWidth = 1;
            //this._ctx.strokeRect(this.xpixel + 10, start_y, this.widthpixel - 20, yoffs);
        }
    }
    /**
     * @param {string} text - Text to break into lines if it is too long
     * @param {number} max_width - Maximum width of the text
     * @description autoLineBreak will break the text into lines if it is too long preferably at a space and if there is no space it will break it at a word
     * @returns {string[]}
     */
    _autoLineBreak(text, maxWidth) {
        //automatically line breaks. Breaks preferably at spaces and if not possible at other places.
        var words = text.split(' ');
        var lines = [];
        var currentLine = '';
        for (var i = 0; i < words.length; i++) {
            var word = words[i];
            var wordWidth = this._ctx.measureText(word).width;
            var width = this._ctx.measureText(currentLine + word).width;
            if (wordWidth > maxWidth) { //if word is too long, break it up into multiple lines
                if (currentLine.length > 0) {
                    lines.push(currentLine);
                }
                currentLine = '';
                var letters_width = 0;
                for (var j = 0; j < word.length; j++) {
                    var letter = word[j];
                    var letterWidth = this._ctx.measureText(letter).width;
                    if (letters_width + letterWidth > maxWidth) {
                        lines.push(currentLine);
                        letters_width = 0;
                        currentLine = '';
                    }
                    currentLine += letter;
                    letters_width += letterWidth;
                }
                currentLine += ' ';
            }
            else {
                if (width > maxWidth) { //if line is too long, break it and add word to next line
                    lines.push(currentLine);
                    currentLine = '';
                }
                currentLine += word + ' ';
            }
        }
        if (currentLine.length > 0) {
            if (currentLine[currentLine.length - 1] == ' ') {
                currentLine = currentLine.substr(0, currentLine.length - 1);
            }
            lines.push(currentLine);
        }
        return lines;
    }
    /**
     * @protected
     */
    _drawTextBox() {
        super._draw();
        this._drawText();
    }
    /**
     * @protected
     */
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
     * @default "0.5 or 12px"
     */

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
    get auto_line_break() {
        return this._auto_line_break;
    }
    /**
     * @param {number} font_size
     * @public - accessible from outside the class
     */
    set font_size(font_size) {
        this._font_size = font_size;
    }
    get font_size() {
        return this._font_size;
    }
}