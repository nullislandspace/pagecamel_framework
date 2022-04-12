class UIButton {
    constructor(canvas) {
        this.hovering_on = null;
        this.buttons = [];
        this.mouse_down_on = null;
    }
    add(options) {
        this.buttons.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            ctx.lineWidth = button.border_width;
            ctx.font = button.font_size + 'px Everson Mono';
            if (i == this.hovering_on) {
                ctx.strokeStyle = button.hover_border;
            }
            else {
                ctx.strokeStyle = button.border;
            }
            var grd;
            if (button.grd_type == 'horizontal') {
                grd = ctx.createLinearGradient(button.x, button.y, button.x + button.width, button.y);
            }
            else if (button.grd_type == 'vertical') {
                grd = ctx.createLinearGradient(button.x, button.y, button.x, button.y + button.height);
            }
            if (button.grd_type) {
                var step_size = 1 / button.background.length;
                if (i == this.mouse_down_on) {
                    ctx.fillStyle = button.background[button.background.length - 1];
                }
                else {
                    for (var j in button.background) {
                        grd.addColorStop(step_size * j, button.background[j]);
                        ctx.fillStyle = grd;
                    }
                }
            }
            if (button.background.length == 1) {
                ctx.fillStyle = button.background[0];
            }
            if (!button.border_radius) {
                ctx.fillRect(button.x, button.y, button.width, button.height);
                ctx.strokeRect(button.x, button.y, button.width, button.height);
            } else {
                roundRect(ctx, button.x, button.y, button.width, button.height, button.border_radius, button.border_width);
            }
            ctx.fillStyle = button.foreground;
            ctx.strokeStyle = button.foreground;
            if (button.displaytext) {
                if (!button.displaytext.includes("\n")) {
                    var text_width = ctx.measureText(button.displaytext).width;
                    if (button.align == 'right') {
                        //align text right
                        ctx.fillText(button.displaytext, button.x + button.width - text_width - 8, button.y + (button.height / 2) + button.font_size / 3.3);
                    }
                    else if (button.align == 'left') {
                        //align text left
                        ctx.fillText(button.displaytext, button.x + 8, button.y + (button.height / 2) + button.font_size / 3.3);
                    }
                    else {
                        //align text center
                        ctx.fillText(button.displaytext, button.x + (button.width - text_width) / 2, button.y + (button.height / 2) + button.font_size / 3.3);
                    }

                } else {
                    var blines = button.displaytext.split("\n");
                    var yoffs = button.y + ((button.height / 2) - (9 * (blines.length - 1)));
                    var j;
                    for (j = 0; j < blines.length; j++) {
                        blines[j].replace("\n", '');
                        ctx.fillText(blines[j], button.x + 8, yoffs);
                        yoffs = yoffs + 18;
                    }
                }
            }
        }
    }
    fileHandler(input){
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button.select_file) {
                console.log(input.files[0]);                
                
            }
        }
    }
    onClick(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button) {
                var startx = button.x;
                var starty = button.y;
                var endx = startx + button.width;
                var endy = starty + button.height;
                if (x >= startx && x <= endx && y >= starty && y <= endy && this.mouse_down_on == i) {
                    if(button.select_file === true){
                        $("#upload").trigger('click');
                    }
                    else{
                        button.callback(button.callbackData);
                    }
                    triggerRepaint();
                }
            }
        }
        this.mouse_down_on = null;
    }
    onMouseDown(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            var startx = button.x;
            var starty = button.y;
            var endx = startx + button.width;
            var endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                this.mouse_down_on = i;
                triggerRepaint();
                return;
            }
        }
        this.mouse_down_on = -1;
        return;
    }
    onMouseUp(x, y) {
        return;
    }
    onMouseMove(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            var startx = button.x;
            var starty = button.y;
            var endx = startx + button.width;
            var endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy && (this.mouse_down_on == null || this.mouse_down_on == i)) {
                this.hovering_on = i;
                triggerRepaint();
                return;
            }
        }
        if (this.hovering_on != null) {
            triggerRepaint();
        }
        this.hovering_on = null;
        return;
    }
    find(name) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button.name == name) {
                return button;
            }
        }
    }
    clear() {
        this.mouse_down_on = null;
        this.hovering_on = null;
        this.buttons = [];
    }
    onKeyDown(e) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            for (var j in button.accept_keycode) {
                if (button.accept_keycode[j] == e.keyCode) {
                    e.preventDefault();
                    button.callback(button.callbackData);
                }
            }

        }
    }
}