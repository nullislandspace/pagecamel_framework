class UITextBox {
    constructor() {
        this.textboxes = [];
    }
    add(options) {
        options.setText = (params) => {
            options.displaytext = params;
        }
        this.textboxes.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.textboxes) {
            var textbox = this.textboxes[i];
            ctx.font = textbox.font_size + 'px Courier';
            ctx.strokeStyle = textbox.border;
            var grd;
            if (textbox.grd_type == 'horizontal') {
                grd = ctx.createLinearGradient(textbox.x, textbox.y, textbox.x + textbox.width, textbox.y);
            }
            else if (textbox.grd_type == 'vertical') {
                grd = ctx.createLinearGradient(textbox.x, textbox.y, textbox.x, textbox.y + textbox.height);
            }
            if (textbox.grd_type) {
                var step_size = 1 / textbox.background.length;

                for (var j in textbox.background) {
                    grd.addColorStop(step_size * j, textbox.background[j]);
                    ctx.fillStyle = grd;

                }
            }
            if (textbox.background.length == 1) {
                ctx.fillStyle = textbox.background[0];
            }
            if (!textbox.border_radius) {
                ctx.fillRect(textbox.x, textbox.y, textbox.width, textbox.height);
                ctx.strokeRect(textbox.x, textbox.y, textbox.width, textbox.height);
            } else {
                roundRect(ctx, textbox.x, textbox.y, textbox.width, textbox.height, textbox.border_radius, textbox.border_width);
            }
            ctx.fillStyle = textbox.foreground;
            ctx.strokeStyle = textbox.foreground;
            if (textbox.displaytext) {
                if (!textbox.displaytext.includes("\n")) {
                    ctx.fillText(textbox.displaytext, textbox.x + 8, textbox.y + (textbox.height / 2));
                } else {
                    var blines = textbox.displaytext.split("\n");
                    var yoffs = textbox.y + ((textbox.height / 2) - (9 * (blines.length - 1)));
                    var j;
                    for (j = 0; j < blines.length; j++) {
                        blines[j].replace("\n", '');
                        ctx.fillText(blines[j], textbox.x + 8, yoffs);
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
        for (var i in this.textboxes) {
            var textbox = this.textboxes[i];
            if (textbox.name == name) {
                return textbox;
            }
        }
    }
}