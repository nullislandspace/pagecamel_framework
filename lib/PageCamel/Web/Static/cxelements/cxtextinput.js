//rewrite UITextInput to CXTextInput
class CXTextInput extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative, redraw) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._text_alignment = 'left';
        super._takes_keyboard_input = true;
        this.type = 'text'; //text, number, float, euro
        this._always_active = false;
        this._cursorPos = 0;
        this._cursor_color = '#000000';
        this._cursor_width = 1;
        this._cursor_active = false;
        this._cursor_blink_interval = 500;
        this._cursor_visible_blink = false;
        this._auto_line_break = false;
        setInterval(() => {
            if (this._cursor_active) {
                this._cursor_visible_blink = !this._cursor_visible_blink;
            }
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }, this._cursor_blink_interval);
    }
    _showCursor(x) {
        var startx = this.xpixel + this._border_width;
        this._ctx.font = this._font_size_pixel + "px " + this._font_family;

        // since the text width gets resized when the text is too long, we need to calculate the cursor position based on the overflow factor 
        var too_long_factor = this._ctx.measureText(this.text).width / (this.widthpixel - this._border_width * 2);
        if (too_long_factor < 1) {
            too_long_factor = 1;
        }
        if (this.text.length > 0) {
            for (var j = 0; j < this.text.length; j++) {
                var new_text = this.text.slice(0, j);
                var new_text_next = this.text.slice(0, j + 1);
                var text_width = this._ctx.measureText(new_text).width / too_long_factor;
                var text_width_next = this._ctx.measureText(new_text_next).width / too_long_factor;
                var letter_width = this._ctx.measureText(new_text.substring(new_text.length - 1)).width / too_long_factor;
                var letter_width_next = this._ctx.measureText(new_text_next.substring(new_text_next.length - 1)).width / too_long_factor;
                var relative_mouse_down = x - startx;
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
            this._cursor_active = true;
            this._has_changed = true;
            if (this._redraw) {
                this.draw(this._px, this._py, this._pwidth, this._pheight);
            }
        }
    }
    _moveCursorLeft(ctrl) {
        this._cursor_visible_blink = true;
        if (this._cursorPos > 0) {
            if (ctrl) {
                var new_text_next = this.text.substring(0, this._cursorPos);
                var new_text_next_words = new_text_next.split(' ');
                this._cursorPos -= new_text_next_words[new_text_next_words.length - 1].length;
            } else {
                this._cursorPos--;
                this._has_changed = true;
            }
        }
    }
    _moveCursorRight(ctrl) {
        this._cursor_visible_blink = true;
        if (this._cursorPos < this.text.length) {
            if (ctrl) {
                var new_text_next = this.text.substring(this._cursorPos + 1);
                var new_text_next_words = new_text_next.split(' ');
                this._cursorPos += new_text_next_words[0].length;
            } else {
                this._cursorPos++;
                this._has_changed = true;
            }
        }
    }
    handleEvent(event) {
        super.handleEvent(event);
        var [x, y] = this._eventToXY(event);
        console.log(event.type);
        if (event.type == 'keydown') {
            console.log(event.key);
            if (this._cursor_active) {
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
                            var new_text = this.text.substring(0, this._cursorPos);
                            var new_text_next = this.text.substring(this._cursorPos + 1);
                            var new_text_next_words = new_text_next.split(' ');
                            new_text_next_words.shift();
                            new_text += new_text_next_words.join(' ');
                            this.text = new_text;
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
                    this.text = this.text.substring(0, this._cursorPos) + event.key + this.text.substring(this._cursorPos);
                    this._cursorPos++;
                    this._has_changed = true;
                    this._cursor_visible_blink = true;
                    event.preventDefault();
                }
            }
        } else if (event.type == 'mousedown') {
            if (this._isInside(x, y)) {
                this._showCursor(x, y);
            }
        } else if (event.type == 'mousemove') {
            //change pointer to text cursor if cursor is inside the text input area 
            if (this._isInside(x, y)) {
                this._ctx.canvas.style.cursor = 'text';
            }
            else {
                this._ctx.canvas.style.cursor = 'default';
            }

        }
        if (this._redraw && this._has_changed) {
            this.draw(this._px, this._py, this._pwidth, this._pheight);
        }
    }
    _drawCursor() {
        if (this._cursor_active && this._cursor_visible_blink) {
            this._ctx.fillStyle = this._cursor_color;
            console.log('draw cursor at: ' + this._cursor_x);
            var text_width = this._ctx.measureText(this.text).width;
            var too_long_factor = text_width / (this.widthpixel - this._border_width * 2);

            var cursor_x = this._ctx.measureText(this.text.substring(0, this._cursorPos)).width + this.xpixel + this._border_width;
            if (too_long_factor > 1) {
                cursor_x = this._ctx.measureText(this.text.substring(0, this._cursorPos)).width / too_long_factor + this.xpixel + this._border_width;
            }
            cursor_x -= this._cursor_width / 2;
            var cursor_y = this.ypixel + this._border_width + this.heightpixel / 2 - this._font_size_pixel / 2;
            this._ctx.fillRect(Math.round(cursor_x), cursor_y, this._cursor_width, this._font_size_pixel);
        }
    }
    _draw() {
        super._draw();
        this._drawCursor();
    }

}
