class UIList {
    constructor() {
        this.lists = []
    }
    new(options) {
        var list = {
            startx: options.x,
            starty: options.y,
            width: options.width,
            height: options.height,
            font_size: options.font_size,
            style: options.style,
            id: options.id,
            type: 'List',
            background: options.background_color,
            foreground: options.foreground_color,
            callback: options.callback.function,
            callbackData: { key: options.callback.key, value: options.callback.value }
        }
        this.lists.push(list);
        return button
    }

    render(ctx) {
        for (let i in this.buttons) {
            let button = this.buttons[i];

        }
    }
    onClick(x, y) {
        for (let i in this.buttons) {

        }
    }
    setList() {

    }
}