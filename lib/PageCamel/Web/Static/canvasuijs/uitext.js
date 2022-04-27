class UIText {
    constructor(canvas) {
        this.texts = [];
        this.canvas = canvas;
    }
    add(options) {
        if (options.active === undefined) {
            options.active = true;
        }
        options.setText = (params) => {
            options.displaytext = params;
            triggerRepaint();
        }
        options.getText = () => {
            return options.displaytext;
        }
        this.texts.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.texts) {
            var text = this.texts[i];
            if (text.active) {
                if (text.height !== undefined) {
                    ctx.font = text.height + 'px Everson Mono';
                }
                else {
                    ctx.font = text.font_size + 'px Everson Mono';
                }
                ctx.save(); //saves the state of canvas
                ctx.translate(text.center_x, text.center_y);
                ctx.rotate(text.angle * Math.PI / 180);
                ctx.translate(-text.center_x, -text.center_y);
                ctx.fillStyle = text.foreground;
                if (text.displaytext) {
                    var text_width = ctx.measureText(text.displaytext).width;
                    if (text.width !== undefined && text.height !== undefined) {
                        if (text_width > text.width) {
                            ctx.fillText(text.displaytext, text.x, text.y + (text.height / 2) + text.height / 3.3, text.width);
                        }
                        else {
                            ctx.fillText(text.displaytext, text.x + (text.width - text_width) / 2, text.y + (text.height / 2) + text.height / 3.3);
                        }
                    } else {
                        ctx.fillText(text.displaytext, text.x, text.y + text.font_size / 3.3);
                    }
                }
                //restore the state of canvas
                ctx.restore();
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
        for (var i in this.texts) {
            var text = this.texts[i];
            if (text.name == name) {
                return text;
            }
        }
    }
    clear() {
        this.texts = [];
    }
}