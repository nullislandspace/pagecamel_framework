class UIText {
    constructor() {
        this.texts = []
    }
    new(options) {
        var text = {
            startx: options.x,
            starty: options.y,
            displaytext: options.name,
            font_size: options.font_size,
            type: 'Text',
            foreground: options.foreground_color,
        }
        this.texts.push(text);
        return text
    }
    render(ctx) {
        for (let i in this.texts) {
            let text = this.texts[i];
            ctx.font = text.font_size + 'px Courier'
            ctx.fillStyle = text.foreground;
            if (!text.displaytext.includes("\n")) {
                ctx.fillText(text.displaytext, text.startx, text.starty + text.font_size /1.7);
            } else {
                var blines = text.displaytext.split("\n");
                var yoffs = text.starty + text.font_size /1.7;
                var j;
                for (j = 0; j < blines.length; j++) {
                    blines[j].replace("\n", '');
                    ctx.fillText(blines[j], text.startx, yoffs);
                    yoffs += text.font_size;
                }
            }
        }
    }
    onClick(x, y) {
    }
}