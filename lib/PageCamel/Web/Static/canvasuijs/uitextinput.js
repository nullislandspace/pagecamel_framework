class UITextInput {
    constructor(canvas) {
        this.textinputs = [];
        canvas = canvas.substring(1, canvas.length);
        this.ctx = document.getElementById(canvas).getContext('2d');
    }
    add(options) {
        if (options.active_on_select === undefined) {
            options.active_on_select = true;
        }
        options.show_cursor = false;
        options.milliseconds = Number(new Date());
        options.textbox = new UITextBox();
        options.textbox.add(options);
        this.textinputs.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
            textinput.textbox.render(ctx);
            if (textinput.mouseDown == true && Number(new Date()) >= textinput.milliseconds + 500) {
                textinput.milliseconds = Number(new Date());
                textinput.show_cursor = !textinput.show_cursor;
            }
            if (textinput.show_cursor == true && textinput.mouseDown == true) {
                var text_width = ctx.measureText(textinput.displaytext).width;
                if (textinput.cursorPos !== undefined && textinput.displaytext !== undefined) {
                    text_width = ctx.measureText(0, textinput.cursorPos).width;
                }

                ctx.beginPath();
                if (textinput.border !== undefined) {
                    ctx.strokeStyle = textinput.border;
                }
                if (textinput.align === 'right') {
                    ctx.moveTo(textinput.x + textinput.width - 8, textinput.y + textinput.height - (textinput.height - textinput.font_size / 2.5));
                    ctx.lineTo(textinput.x + textinput.width - 8, textinput.y + (textinput.height - textinput.font_size / 2.5));
                }
                else if (textinput.align === 'left') {
                    ctx.moveTo(textinput.x + 8 + text_width, textinput.y + textinput.height - (textinput.height - textinput.font_size / 2.5));
                    ctx.lineTo(textinput.x + 8 + text_width, textinput.y + (textinput.height - textinput.font_size / 2.5));
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
                        if (textinput.align == 'left') {
                            if (x - startx + 8 > text_width - this.ctx.measureText(textinput.displaytext[j].width) / 2 && x - startx + 8 < text_width_next - this.ctx.measureText(textinput.displaytext[j]).width / 2) {
                                console.log(new_text, new_text_next);
                                textinput.cursorPos = j;
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
        }
    }
    onKeyDown(e) {
        for (var i in this.textinputs) {
            var textinput = this.textinputs[i];
        }
    }
    onKeyUp(e) {
        for (var i in this.buttonrows) {
            var textinput = this.textinputs[i];
        }
    }
    find(name) {
        return;
    }
}