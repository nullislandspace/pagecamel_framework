class UITextBox {
    constructor(canvas) {
        this.textboxes = [];
        this.canvas = canvas;
    }
    add(options) {
        /*if(options.displaytext === undefined){
            options.displaytext = '';
        }*/
        if (options.active === undefined) {
            options.active = true;
        }
        options.setText = (params) => {
            options.displaytext = params;
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
                if (textbox.displaytext) {
                    if (!textbox.displaytext.includes("\n")) {
                        var text_width = ctx.measureText(textbox.displaytext).width;
                        if (textbox.align == 'right') {
                            //align text right
                            ctx.fillText(textbox.displaytext, textbox.x + textbox.width - text_width - 8, textbox.y + (textbox.height / 2) + textbox.font_size / 3.3);
                        }
                        else if (textbox.align == 'left') {
                            //align text left
                            ctx.fillText(textbox.displaytext, textbox.x + 8, textbox.y + (textbox.height / 2) + textbox.font_size / 3.3);
                        }
                        else {
                            //align text center
                            ctx.fillText(textbox.displaytext, textbox.x + (textbox.width - text_width) / 2, textbox.y + (textbox.height / 2) + textbox.font_size / 3.3);
                        }
                    } else {
                        var blines = textbox.displaytext.split("\n");
                        var yoffs = textbox.y + ((textbox.height / 2) - (9 * (blines.length - 1)));
                        for (var j = 0; j < blines.length; j++) {
                            if (textbox.align == 'right') {
                                blines[j].replace("\n", '');
                                var text_width = ctx.measureText(blines[j]).width;
                                ctx.fillText(blines[j], textbox.x + textbox.width - text_width - 8, yoffs);
                            }
                            else {
                                blines[j].replace("\n", '');
                                ctx.fillText(blines[j], textbox.x + 8, yoffs);
                            }
                            yoffs = yoffs + 18;
                        }
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