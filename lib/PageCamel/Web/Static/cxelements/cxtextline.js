class CXTextLine extends CXTextBox { //recreation of uiscolllist.js
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);
    }
    _drawTextLine() {
        //draw the text line
        this._drawBox();
        this._drawText();
    }
    _getTextLineHeight(text) {
        var text_metrics = this.ctx.measureText(text); // get the text metrics for each line
        var actualHeight = text_metrics.actualBoundingBoxAscent + text_metrics.actualBoundingBoxDescent; // get the actual height of the text
        return actualHeight;
    }
    draw() {
        this._drawTextLine();
    }
    _drawText() {
        ctx.fillStyle = this.text_color;
        ctx.font = this.font_size + "em " + this.text_font;
        
        if (this.start_text) {
            ctx.textAlign = 'start';
            var text_height = this._getTextLineHeight(this.start_text);
            ctx.fillText(this.start_text, this._xpos, this._ypos + this._height / 2 - text_height / 2 + text_height);
        }
        if (this.center_text) {
            ctx.textAlign = 'center';
            var text_height = this._getTextLineHeight(this.center_text);
            ctx.fillText(this.center_text, this._xpos + this._width / 2, this._ypos + this._height / 2 - text_height / 2 + text_height);
            
        }
        if (this.end_text) {
            ctx.textAlign = 'end';
            var text_height = this._getTextLineHeight(this.end_text);
            ctx.fillText(this.end_text, this._xpos + this._width, this._ypos + this._height / 2 - text_height / 2 + text_height);
        }
        if (this.text_repeat) {
            ctx.textAlign = 'start';
            var text_height = this._getTextLineHeight(this.text_repeat);
            ctx.fillText(this.text_repeat, this._xpos, this._ypos + this._height / 2 - text_height / 2 + text_height);
        }
    }
    setText(start_text, center_text, end_text) {
        this.start_text = start_text;
        this.center_text = center_text;
        this.end_text = end_text;
        this.text_repeat = null;
    }
    repeatText(text) {
        var text_width = this.ctx.measureText(text).width;
        var text_repeat = text;
        for (var i; i < 500; i++) {
            text_width += this.ctx.measureText(text_repeat + text).width;
            if (text_width > this._width) {
                break;
            }
            text_repeat += text;
        }
        this.text_repeat = text_repeat;
        this.start_text = null;
        this.center_text = null;
        this.end_text = null;
    }
}