import { CXTextBox } from "./cxtextbox.js";
export class CXTextInput extends CXTextBox {
    /** @protected */
    protected _cursorPos: number;
    /** @protected */
    protected _cursor_color: string;
    /** @protected */
    protected _cursor_width: number;
    /** @protected */
    protected _cursor_active: boolean;
    /** @protected */
    protected _cursor_blink_interval: number;
    /** @protected */
    protected _cursor_visible_blink: boolean;
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
        super._text_alignment = 'left';
        super._takes_keyboard_input = true;
        super._auto_line_break = false;
        this._cursorPos = 0;
        this._cursor_color = '#000000';
        this._cursor_width = 1;
        this._cursor_active = false;
        this._cursor_blink_interval = 500;
        this._cursor_visible_blink = false;
        this._name = 'CXTextInput';
        setInterval(() => {
            if (this._cursor_active) {
                this._cursor_visible_blink = !this._cursor_visible_blink;
            }
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }, this._cursor_blink_interval);
    }
    /**
     * @param {number} x the x coordinate of the mouse 
     * @description converts the mouse coordinates to the cursor position in the text
     */
    _showCursor(x: number): void {
        var startx = this.xpixel + this._border_width;
        this._ctx.font = this._font_size_pixel + "px " + this._font_family;
        if (this.text.length > 0) {
            for (var j = 0; j < this.text.length; j++) {
                var new_text = this.text.slice(0, j);
                var new_text_next = this.text.slice(0, j + 1);
                var text_width = this._ctx.measureText(new_text).width;
                var text_width_next = this._ctx.measureText(new_text_next).width;
                var letter_width = this._ctx.measureText(new_text.substring(new_text.length - 1)).width;
                var letter_width_next = this._ctx.measureText(new_text_next.substring(new_text_next.length - 1)).width;
                var relative_mouse_down = x - startx - 8;
                if (this._text_alignment == 'left') {
                    if (relative_mouse_down > text_width - letter_width / 2 && relative_mouse_down < text_width_next - letter_width_next / 2) {
                        //when cursor should be inside the text
                        this._cursorPos = new_text.length;
                        break
                    }
                    else if (relative_mouse_down > this._ctx.measureText(this.text).width - this._ctx.measureText(this.text.substring(this.text.length - 1)).width / 2) {
                        //when cursor should be at the end
                        this._cursorPos = this.text.length;
                        break
                    }
                    else if (relative_mouse_down < this._ctx.measureText(this.text.substring(0, 1)).width / 2) {
                        //when cursor should be at the beginning
                        this._cursorPos = 0;
                        break
                    }
                }
            }
        }
        this._cursor_active = true;
        this._has_changed = true;
        this._tryRedraw();
    }
    /**
     * @param {boolean} ctrl - if the control key is pressed
     * @protected
     */
    protected _moveCursorLeft(ctrl: boolean): void {
        this._cursor_visible_blink = true;
        if (this._cursorPos > 0) {
            if (ctrl) {
                // move cursorPos to the beginning of the word if ctrl is pressed
                var new_text = this.text.slice(0, this._cursorPos);
                console.log(new_text);
                //cut the last spaces from the text
                new_text = new_text.replace(/\s+$/, '');
                this._cursorPos = new_text.lastIndexOf(' ') + 1;
                if (new_text.lastIndexOf(' ') == -1) {
                    this._cursorPos = 0;
                }
            } else {
                this._cursorPos--;
            }
            this._has_changed = true;
        }
    }
    /**
     * @param {boolean} ctrl - if the control key is pressed
     * @protected
     */
    protected _moveCursorRight(ctrl: boolean): void {
        this._cursor_visible_blink = true;
        if (this._cursorPos < this.text.length) {
            if (ctrl) {
                // move to the end of the word if ctrl is pressed
                var new_text = this.text.slice(this._cursorPos);
                //cut the first spaces from the text
                new_text = new_text.replace(/^\s+/, '');
                console.log(new_text);
                var index_from_end = new_text.length - new_text.indexOf(' ');
                this._cursorPos = this.text.length - index_from_end;
                if (new_text.indexOf(' ') == -1) {
                    this._cursorPos = this.text.length;
                }

            } else {
                this._cursorPos++;
            }
            this._has_changed = true;
        }
    }
    /**
     * @protected
     * @description overwritten the checkMouseDown function to handle event when clicked outside the text input, so the cursor gets disabled 
     */
    protected _checkMouseDown(x: number, y: number): boolean {
        // overwritten the checkMouseDown function to handle event when clicked outside the text input, so the cursor gets disabled
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            this._mouse_down = true;
            return true;
        }
        this._mouse_down = false;
        return true;
    }
    /**
     * @param {event} event - the event object
     * @protected
     * @description changes the text when a key is pressed
     */
    protected _changeText(event: KeyboardEvent): void {
        var ctrl = event.ctrlKey;
        console.log(event)
        if (event.key == 'ArrowLeft') {
            this._moveCursorLeft(ctrl);
            event.preventDefault();
        }
        else if (event.key == 'ArrowRight') {
            this._moveCursorRight(ctrl);
            event.preventDefault();
        }
        else if (event.key == 'Backspace') {
            if (this._cursorPos > 0) {
                if (ctrl) {
                    //delete one word
                    var new_text = this.text.substring(0, this._cursorPos).split(' ');
                    new_text.splice(new_text.length - 1, 1);
                    this.text = new_text.join(' ');
                }
                else {
                    this.text = this.text.substring(0, this._cursorPos - 1) + this.text.substring(this._cursorPos);
                    this._cursorPos--;
                    console.log(this._cursorPos);
                    this._cursor_visible_blink = true;
                }
                this._has_changed = true;
                event.preventDefault();
            }
        }
        else if (event.key == 'Delete') {
            if (this._cursorPos < this.text.length) {
                if (ctrl) {
                    //delete one word
                    var new_text2 = this.text.substring(0, this._cursorPos);
                    var new_text_next = this.text.substring(this._cursorPos + 1);
                    var new_text_next_words = new_text_next.split(' ');
                    new_text_next_words.shift();
                    new_text2 += new_text_next_words.join(' ');
                    this.text = new_text2;
                }
                else {
                    this.text = this.text.substring(0, this._cursorPos) + this.text.substring(this._cursorPos + 1);
                    this._cursor_visible_blink = true;
                }
                this._has_changed = true;
                event.preventDefault();
            }
        }
        else if (event.key.length == 1) {
            var new_text3 = this.text.substring(0, this._cursorPos) + event.key + this.text.substring(this._cursorPos);
            if (this._ctx.measureText(new_text3).width <= this._widthpixel - this._border_width * 2 - 8) {
                this.text = new_text3;
                this._cursorPos++;
                this._has_changed = true;
                this._cursor_visible_blink = true;
                event.preventDefault();
            }
        }
    }
    /**
     * @protected
     * @description return true if the text should be changed by the event | false if not
     * @param {event} event - the event object
     * @returns {boolean}
     */
    protected _onKeyDown(event: KeyboardEvent): boolean {
        //overwrite if different behaviour is needed
        return true;
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @protected
     */
    protected _handleEvent(event: Event): boolean {
        super._handleEvent(event);

        console.log('TextInput Event:', event.type);
        if (event.type == 'keydown') {
            var e = event as KeyboardEvent;
            console.log(e.key);
            if (this._cursor_active) {
                var handlekey = this._onKeyDown(e);
                if (handlekey) {
                    this._changeText(e);
                }
            }
        } else if (event.type == 'mousedown') {
            var [x, y] = this._eventToXY(event as MouseEvent);
            if (this._isInside(x, y)) {
                this._showCursor(x);
            }
            else {
                this._cursor_active = false;
            }
        } else if (event.type == 'mousemove') {
            var [x, y] = this._eventToXY(event as MouseEvent);
            //change pointer to text cursor if cursor is inside the text input area 
            if (this._isInside(x, y)) {
                this._ctx.canvas.style.cursor = 'text';
            }
            else {
                this._ctx.canvas.style.cursor = 'default';
            }

        }
        this._tryRedraw();
        return this._has_changed;
    }
    /**
     * @protected
     */
    protected _drawCursor(): void {
        if (this._cursor_active && this._cursor_visible_blink) {
            this._ctx.fillStyle = this._cursor_color;
            var cursor_x = this._ctx.measureText(this.text.substring(0, this._cursorPos)).width + this.xpixel + this._border_width + 8;
            cursor_x -= this._cursor_width / 2;
            var cursor_y = this.ypixel + this._border_width + this.heightpixel / 2 - this._font_size_pixel / 2;
            this._ctx.fillRect(Math.round(cursor_x), cursor_y, this._cursor_width, this._font_size_pixel);
        }
    }
    /**
     * @protected
     */
    _draw(): void {
        super._draw();
        this._drawCursor();
    }
}