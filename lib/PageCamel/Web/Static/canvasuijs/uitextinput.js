class UITextInput {
    constructor(canvas) {
        this.textinputs = [];
        this.canvas = canvas;
        canvas = canvas.substring(1, canvas.length);
        this.ctx = document.getElementById(canvas).getContext('2d');
        this.pressedKey = new GetPressedKeyChar();
    }
    add(options) {
        if (options.active_on_select === undefined) {
            options.active_on_select = true;
        }
        if (options.type === undefined) {
            options.type = 'text';
        }
        options.getText = () => {
            return options.displaytext;
        }
        options.setText = (text) => {
            options.displaytext = text;
        }
        options.always_show_cursor = false;
        options.cursorPos = 0;
        options.show_cursor = false;
        options.milliseconds = Number(new Date());
        options.displaytext.toString();
        options.textbox = new UITextBox();
        options.textbox.add(options);
        this.textinputs.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            textinput.textbox.render(ctx);
            ctx.font = textinput.font_size + 'px Everson Mono';
            if (textinput.label !== undefined) {
                var label_width = ctx.measureText(textinput.label).width;
                ctx.fillText(textinput.label, textinput.x - label_width - 5, textinput.y + (textinput.height / 2) + textinput.font_size / 3.3);

            }

            if (textinput.mouseDown == true && Number(new Date()) >= textinput.milliseconds + 500) {
                textinput.milliseconds = Number(new Date());
                textinput.show_cursor = !textinput.show_cursor;
            }
            if (textinput.show_cursor == true && textinput.mouseDown == true || textinput.always_show_cursor == true) {
                var text_width = ctx.measureText(textinput.displaytext).width;
                if (textinput.cursorPos !== undefined && textinput.displaytext !== undefined) {
                    text_width = ctx.measureText(textinput.displaytext.slice(0, textinput.cursorPos)).width;
                }

                ctx.beginPath();
                if (textinput.border !== undefined) {
                    ctx.strokeStyle = textinput.border;
                }
                if (textinput.align === 'right') {
                    ctx.moveTo(textinput.x + textinput.width - 8, textinput.y + textinput.height / 2 - textinput.font_size / 2);
                    ctx.lineTo(textinput.x + textinput.width - 8, textinput.y + textinput.height / 2 + textinput.font_size / 2);
                }
                else if (textinput.align === 'left') {
                    ctx.moveTo(textinput.x + 8 + text_width, textinput.y + textinput.height / 2 - textinput.font_size / 2);
                    ctx.lineTo(textinput.x + 8 + text_width, textinput.y + textinput.height / 2 + textinput.font_size / 2);
                }
                else {

                }
                ctx.stroke();
            }
        }
    }
    onClick(x, y) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
        }
    }
    onMouseDown(x, y) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            var startx = textinput.x;
            var starty = textinput.y;
            var endx = startx + textinput.width;
            var endy = starty + textinput.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                textinput.mouseDown = true;
                if (textinput.displaytext.length > 0) {
                    for (var j = 0; j < textinput.displaytext.length; j++) {
                        this.ctx.font = textinput.font_size + 'px Everson Mono';
                        var new_text = textinput.displaytext.slice(0, j);
                        var new_text_next = textinput.displaytext.slice(0, j + 1);
                        var text_width = this.ctx.measureText(new_text).width;
                        var text_width_next = this.ctx.measureText(new_text_next).width;
                        var letter_width = this.ctx.measureText(new_text.substring(new_text.length - 1)).width;
                        var letter_width_next = this.ctx.measureText(new_text_next.substring(new_text_next.length - 1)).width;
                        var relative_mouse_down = x - startx - 8;
                        textinput.show_cursor = false;
                        if (textinput.align == 'left') {
                            if (relative_mouse_down > text_width - letter_width / 2 && relative_mouse_down < text_width_next - letter_width_next / 2) {
                                //when cursor should be inside the text
                                textinput.cursorPos = new_text.length;
                                break
                            }
                            else if (relative_mouse_down > this.ctx.measureText(textinput.displaytext).width - this.ctx.measureText(textinput.displaytext.substring(textinput.displaytext.length - 1)).width / 2) {
                                //when cursor should be at the end
                                textinput.cursorPos = textinput.displaytext.length;
                                break
                            }
                            else if (relative_mouse_down < this.ctx.measureText(textinput.displaytext.substring(0, 1)).width / 2) {
                                //when cursor should be at the beginning
                                textinput.cursorPos = 0;
                                break
                            }
                        }
                    }
                }

                triggerRepaint();
            }
            else if (textinput.mouseDown) {
                textinput.mouseDown = false;
                triggerRepaint();
            }
        }
    }
    onMouseUp(x, y) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
        };
    }
    onMouseMove(x, y) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            var startx = textinput.x;
            var starty = textinput.y;
            var endx = startx + textinput.width;
            var endy = starty + textinput.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                $(this.canvas).css('cursor', 'text');
                return
            }
        }
        //$(this.canvas).css('cursor', 'default');
    }
    onKeyDown(e) {
        var keyCode = e.keyCode;
        var char = this.pressedKey.keydown(e);
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            if (textinput.mouseDown) {
                if (keyCode == 37) {
                    //left
                    if (textinput.cursorPos > 0) {
                        textinput.always_show_cursor = true;
                        textinput.cursorPos -= 1;
                    }
                }
                if (keyCode == 39) {
                    //right
                    if (textinput.cursorPos < textinput.displaytext.length) {
                        textinput.always_show_cursor = true;
                        textinput.cursorPos += 1;
                    }
                }
                if (char !== 'delete' && char !== 'backspace' && char !== undefined) {
                    var first_text_part = textinput.displaytext.slice(0, textinput.cursorPos);
                    var last_text_part = textinput.displaytext.slice(textinput.cursorPos, textinput.displaytext.length);
                    if (textinput.type == 'text') {
                        textinput.displaytext = first_text_part + char + last_text_part;
                        textinput.cursorPos += 1;
                        textinput.always_show_cursor = true;
                    }
                    else if (textinput.type == 'number' && char >= 0) {
                        textinput.displaytext = first_text_part + char + last_text_part;
                        textinput.cursorPos += 1;
                        textinput.always_show_cursor = true;
                    }

                } else if (char === 'backspace' && textinput.cursorPos > 0) {
                    var first_text_part = textinput.displaytext.slice(0, textinput.cursorPos - 1);
                    var last_text_part = textinput.displaytext.slice(textinput.cursorPos, textinput.displaytext.length);
                    textinput.displaytext = first_text_part + last_text_part;
                    textinput.always_show_cursor = true;
                    textinput.cursorPos -= 1;
                }
                else if (char === 'delete' && textinput.cursorPos < textinput.displaytext.length) {
                    var first_text_part = textinput.displaytext.slice(0, textinput.cursorPos);
                    var last_text_part = textinput.displaytext.slice(textinput.cursorPos + 1, textinput.displaytext.length);
                    textinput.displaytext = first_text_part + last_text_part;
                    textinput.always_show_cursor = true;
                }
                if (textinput.callback !== undefined) {
                    textinput.callback(textinput.displaytext);
                }
                triggerRepaint();
            }
        }
    }
    onKeyUp(e) {
        this.pressedKey.keyup(e);
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            textinput.always_show_cursor = false;
        }
    }
    find(name) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            if (textinput.name == name) {
                return textinput;
            }
        }
    }
    clear() {
        this.textinputs = [];
    }
}