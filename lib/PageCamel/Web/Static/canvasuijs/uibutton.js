class UIButton {
    constructor() {
        this.onHover = this.onHover.bind(this);
        this.hovering_on = null;
        this.buttons = [];
        this.clicked_on = -1;
    }
    add(options) {
        this.buttons.push(options);
        console.log(this.buttons);
        return options;
    }
    render(ctx) {
        //console.log(this);
        for (var i in this.buttons) {
            let button = this.buttons[i];
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
                if (i == this.clicked_on) {
                    //console.log(this);
                    //console.log(this.clicked_on);
                    this.clicked_on = -1;
                    //var reversed_background = button.background.reverse();
                    button.background.reverse();/*
                    for (var j in reversed_background) {
                        grd.addColorStop(step_size * j, reversed_background[j]);
                    }*/
                }
                else {
                    for (var j in button.background) {
                        grd.addColorStop(step_size * j, button.background[j]);
                    }
                }
                ctx.fillStyle = grd;
            }
            if (button.background.length == 1) {
                ctx.fillStyle = button.background[0];
            }
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
    endClick(){
        console.log('111')
        this.clicked_on = -1;
        console.log("ENDCLICK");
        console.log(this);
    }
    onClick(x, y) {
        console.log(this);
        for (let i in this.buttons) {
            let button = this.buttons[i];
            let startx = button.x;
            let starty = button.y;
            let endx = startx + button.width;
            let endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                this.clicked_on = i;
                //setTimeout(this.endClick, 200);
                button.callback(button.callbackData);
                console.log("ONCLICK " + i);
                console.log(this);
            }
        }
    }
    onHover(x, y) {
        for (let i in this.buttons) {
            let button = this.buttons[i];
            let startx = button.x;
            let starty = button.y;
            let endx = startx + button.width;
            let endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                this.hovering_on = i;
                return;
            }
        }
        this.hovering_on = null;
        return;
    }
}