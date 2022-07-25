class UITextBox {
    constructor(canvas) {
        this.textboxes = [];
        this.canvas = canvas;
    }
    add(options) {
        if (options.displaytext === undefined) {
            options.displaytext = '';
        } else {
            options.displaytext = String(options.displaytext);
        }
        if (options.active === undefined) {
            options.active = true;
        }
        options.setText = (params) => {
            options.displaytext = String(params);
            triggerRepaint();
        }
        options.getText = () => {
            if (options.displaytext !== undefined) {
                return options.displaytext;
            }
            else {
                return ''
            }
        }
        this.textboxes.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.textboxes) {
            var textbox = this.textboxes[i];
            if (textbox.active) {
                if (textbox.highlight && (textbox.main_highlight != textbox.displaytext || textbox.displaytext === undefined)) {
                    ctx.strokeStyle = '#ff0000';
                    ctx.lineWidth = 8;
                }
                else if (textbox.main_highlight != textbox.displaytext || textbox.displaytext === undefined) {
                    ctx.strokeStyle = textbox.border;
                    ctx.lineWidth = textbox.border_width;
                }
                else if (textbox.displaytext !== undefined) {
                    ctx.strokeStyle = '#00ffff';
                    ctx.lineWidth = 8;
                }
                ctx.font = textbox.font_size + 'px Everson Mono';
                ctx.save(); //saves the state of canvas

                ctx.translate(textbox.center_x, textbox.center_y);
                ctx.rotate(textbox.angle * Math.PI / 180);
                ctx.translate(-textbox.center_x, -textbox.center_y);
                //restore the state of canvas
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
                    if (textbox.border_width != 0 && textbox.border_width != undefined) {
                        ctx.strokeRect(textbox.x, textbox.y, textbox.width, textbox.height);
                    }
                } else {
                    roundRect(ctx, textbox.x, textbox.y, textbox.width, textbox.height, textbox.border_radius, textbox.border_width);
                }
                ctx.restore();
                ctx.fillStyle = textbox.foreground;
                ctx.strokeStyle = textbox.foreground;
                if (textbox.label !== undefined) {
                    var label_width = ctx.measureText(textbox.label).width;
                    ctx.fillText(textbox.label, textbox.x - label_width - 5, textbox.y + (textbox.height / 2) + textbox.font_size / 3.3);
                }
                if (textbox.displaytext) {
                    if (!Array.isArray(textbox.displaytext)) { // check if it's an array
                        textbox.displaytext = [textbox.displaytext];
                    }
                    var new_displaytext = [];
                    for (var j in textbox.displaytext) {
                        if (textbox.border_width > 0) {
                            var new_lines = autoLineBreak(ctx, textbox.displaytext[j], textbox.width - textbox.border_width * 2);
                        } else {
                            var new_lines = autoLineBreak(ctx, textbox.displaytext[j], textbox.width);
                        }
                        if (new_lines.length > 0) {
                            new_displaytext = [...new_displaytext, ...new_lines];
                        }
                    }
                    var yoffs = textbox.y + (textbox.height / 2) + textbox.font_size / 3.3;
                    if (new_displaytext.length > 1) {
                        yoffs = textbox.y + textbox.height / 2 - ((new_displaytext.length - 1) * (textbox.font_size * 0.80)) / 2;
                    }
                    for (j = 0; j < new_displaytext.length; j++) {
                        var text_width = ctx.measureText(new_displaytext[j]).width;
                        if (textbox.align == 'right') {
                            //align text right
                            ctx.fillText(new_displaytext[j], textbox.x + textbox.width - text_width - 8, yoffs);
                        }
                        else if (textbox.align == 'left') {
                            //align text left
                            ctx.fillText(new_displaytext[j], textbox.x + 8, yoffs);
                        }
                        else {
                            //align text center
                            ctx.fillText(new_displaytext[j], textbox.x + (textbox.width / 2) - (text_width / 2), yoffs);
                        }
                        yoffs = yoffs + textbox.font_size * 1.1;
                    }
                }
            }
        }
    }
    onClick(x, y) {
        return;
    }
    onMouseDown(x, y) {
        return;
    }
    onMouseUp(x, y) {
        return;
    }
    onMouseMove(x, y) {
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
    clear() {
        this.textboxes = [];
    }
}
canvasuijs.addType('TextBox', UITextBox);