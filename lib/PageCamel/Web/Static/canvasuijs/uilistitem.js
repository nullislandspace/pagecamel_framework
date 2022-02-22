class UIListItem {
    constructor() {
        this.listitems = [];
    }
    add(options) {
        this.listitems.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.listitems) {
            var listitem = this.listitems[i];
            ctx.fillStyle = listitem.selectedBackground;
            var selected = listitem.selected;
            if (selected == listitem.id) {
                ctx.fillRect(listitem.x + listitem.border_width / 1.8, listitem.y + listitem.border_width / 2, listitem.width - listitem.border_width * 1.2, listitem.height);
            }
            var type = listitem.type;
            ctx.fillStyle = listitem.foreground;
            ctx.strokeStyle = listitem.foreground;
            ctx.font = listitem.font_size + 'px Courier';
            for (var j in listitem.lineitem) {
                var lineitem = listitem.lineitem[j];
                if (type == "text") {
                    if (lineitem.align == 'right') {
                        var x = listitem.x + listitem.width * lineitem.location
                        ctx.fillText(lineitem.displaytext, x, listitem.y + listitem.height / 2 + listitem.font_size / 2.7);
                    }
                    else if (lineitem.align == 'left') {
                        var x = listitem.x + listitem.width * lineitem.location - ctx.measureText(lineitem.displaytext).width
                        ctx.fillText(lineitem.displaytext, x, listitem.y + listitem.height / 2 + listitem.font_size / 2.7);
                    }
                    else if (lineitem.align == 'center') {
                        //Center Text
                    }
                }
            }

        }
    }

    onClick(x, y) {
        for (var i in this.listitems) {
            var listitem = this.listitems[i];
            var startx = listitem.x + listitem.border_width / 1.8;
            var starty = listitem.y + listitem.border_width / 2;
            var endx = listitem.width - listitem.border_width * 1.2 + startx;
            var endy = starty + listitem.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                listitem.callback(listitem.id);
            }
        }
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
    onMouseMove(x, y) {
        return;
    }
    find(name) {
        return;
    }
    clear() {
        this.listitems = [];
    }
}