class UIButton {
    constructor() {
        this.buttons = [];
    }
    new(options) {
        this.buttons.push(options);
        console.log(this.buttons);
        return options;
    }
    render(ctx) {
        //console.log(this.buttons)
        for (let i in this.buttons) {
            let button = this.buttons[i];
            ctx.font = button.font_size + 'px Courier';
            ctx.strokeStyle = button.background;
            ctx.fillStyle = button.background;
            if (!button.border_radius) {
                ctx.fillRect(button.x, button.y, button.width, button.height);
                ctx.strokeRect(button.x, button.y, button.width, button.height);
            } else {
                roundRect(ctx, button.x, button.y, button.width, button.height, button.border_radius);
            }
            ctx.fillStyle = button.foreground;
            ctx.strokeStyle = button.foreground;
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
    onClick(x, y) {
        for (let i in this.buttons) {
            let button = this.buttons[i];
            let startx = button.x;
            let starty = button.y;
            let endx = startx + button.width;
            let endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                button.callback(button.callbackData);
            }
        }
    }
}