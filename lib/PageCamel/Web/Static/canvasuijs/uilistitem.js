class UIListItems {
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
        }
    }
    onClick(x, y) {
        for (var i in this.listitems) {
            var listitem = this.listitems[i];
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
    find(name) {
        return;
    }
}