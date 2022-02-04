class UIText {
    constructor() {
        this.texts = []
    }
    new(options) {
        this.texts.push(options);
        return options
    }
    render(ctx) {
        for (let i in this.texts) {
            let text = this.texts[i];
            ctx.font = text.font_size + 'px Courier'
            ctx.fillStyle = text.foreground;
            if (!text.displaytext.includes("\n")) {
                ctx.fillText(text.displaytext, text.x, text.y + text.font_size /1.7);
            } else {
                var blines = text.displaytext.split("\n");
                var yoffs = text.y + text.font_size /1.7;
                var j;
                for (j = 0; j < blines.length; j++) {
                    blines[j].replace("\n", '');
                    ctx.fillText(blines[j], text.x, yoffs);
                    yoffs += text.font_size;
                }
            }
        }
    }
    onClick(x, y) {
    }
}