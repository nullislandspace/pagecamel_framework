class UIPayList {

        constructor() {
            this.paylists = [];
        }
        add(options) {
            this.paylists.push(options);
            return options;
        }
        render(ctx) {
            for (var i in this.buttons) {
                var button = this.buttons[i];
                ctx.font = button.font_size + 'px Courier';
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
                        ctx.fillText(button.displaytext, button.x + 8, button.y + (button.height / 2));
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
        onClick(x, y) {
            return;
        }
        onHover(x, y) {
            return;
        }
        onMouseDown(x, y) {
            return;
        }
        onMouseUp(x, y) {
            return;
        }
        find(name) {
         return;   
        }
    
}