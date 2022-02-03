class UIButton {
    constructor() {
        this.buttons = []
    }
    new(options) {
        var button = {
            startx: options.x,
            starty: options.y,
            width: options.width,
            height: options.height,
            displaytext: options.name,
            font_size: options.font_size,
            style: options.style,
            type: 'Button',
            background: options.background_color,
            foreground: options.foreground_color,
            callback: options.callback.function,
            callbackData: { key: options.callback.key, value: options.callback.value }
        }
        this.buttons.push(button);
        return button
    }
    render(ctx) {
        for (let i in this.buttons) {
            let button = this.buttons[i];
            ctx.font = button.font_size + 'px Courier'
            ctx.strokeStyle = button.background;
            ctx.fillStyle = button.background;
            if (button.style != 'rounded') {
                ctx.fillRect(button.startx, button.starty, button.width, button.height);
                ctx.strokeRect(button.startx, button.starty, button.width, button.height);
            } else {
                roundRect(ctx, button.startx, button.starty, button.width, button.height, 5);
            }
            ctx.fillStyle = button.foreground;
            ctx.strokeStyle = button.foreground;
            if (!button.displaytext.includes("\n")) {
                ctx.fillText(button.displaytext, button.startx + 8, button.starty + (button.height / 2));
            } else {
                var blines = button.displaytext.split("\n");
                var yoffs = button.starty + ((button.height / 2) - (9 * (blines.length - 1)));
                var j;
                for (j = 0; j < blines.length; j++) {
                    blines[j].replace("\n", '');
                    ctx.fillText(blines[j], button.startx + 8, yoffs);
                    yoffs = yoffs + 18;
                }
            }
        }
    }
    onClick(x, y) {
        for (let i in this.buttons) {
            let button = this.buttons[i]
            let startx = button.startx;
            let starty = button.starty;
            let endx = startx + button.width;
            let endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                button.callback(button.callbackData)
            }
        }
    }
}