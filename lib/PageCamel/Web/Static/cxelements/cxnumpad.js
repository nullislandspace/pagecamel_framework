import { CXDefault } from "./cxdefault";
export class CXNumPad extends CXDefault {
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        /** @protected */
        this._buttons_text_block = [['7', '8', '9'], ['4', '5', '6'], ['1', '2', '3'], ['+/-', '0', ',']];

        /** @protected */
        this._buttons = [];
        /** @protected */
        this._gap = 0.02;
        var button_width = (1 - this._gap * 4) / 3;
        var button_height = (1 - this._gap * 5) / this._buttons_text_block.length;
        /** @protected */
        this._font_size = 0.5;
        /** @protected */
        this._name = "CXNumPad";
        for (var i = 0; i < this._buttons_text_block.length; i++) {
            var row = [];
            for (var j = 0; j < this._buttons_text_block[i].length; j++) {
                var button = new CXButton(this._ctx, this._gap + j * (button_width + this._gap), this._gap + i * (button_height + this._gap), button_width, button_height, true, true);
                button.text = this._buttons_text_block[i][j];
                button.allow_hover = true;
                button.hover_border_color = '#ffffff';
                button.gradient = ['#f9a004', '#ff0202'];
                button.text_color = '#000000';
                button.border_color = '#ff0000';
                button.font_size = this._font_size;
                button.radius = 0.1;
                button._draw();
                row.push(button);
            }
            this._buttons.push(row);
        }
    }
    /**
     * @description Draws the buttons of the num pad
     * @protected
     */
    _drawNumpad() {
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                this._buttons[i][j].draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
            }
        }
    }
    /**
     * @protected
     */
    _draw() {
        this._drawNumpad();
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    handleEvent(event) {
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                if (this._buttons[i][j].checkEvent(event)) {
                    this._buttons[i][j].handleEvent(event);
                }
            }
        }
    }
    /** 
     * @param {number} value - Font size in either pixels or relative to button size
     * @description Sets the font size of the text in the button
     */
    set font_size(value) {
        this._font_size = value;
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                this._buttons[i][j].font_size = value;
            }
        }
    }
    get font_size() {
        return this._font_size;
    }
    /**
     * @param {number} value - The gap between buttons in either pixels or relative to button size
     * @description Sets the gap between buttons
     */
    set gap(value) {
        this._gap = value;
        var button_width = (1 - this._gap * 4) / 3;
        var button_height = (1 - this._gap * 5) / 5;
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                this._buttons[i][j].x = this._gap + j * (button_width + this._gap);
                this._buttons[i][j].y = this._gap + i * (button_height + this._gap);
                this._buttons[i][j].width = button_width;
                this._buttons[i][j].height = button_height;
            }
        }
    }
    get gap() {
        return this._gap;
    }
}