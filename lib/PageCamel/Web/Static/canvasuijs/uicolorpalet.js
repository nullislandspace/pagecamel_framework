class UIColorPalet {
    constructor(canvas) {
        this.canvas = canvas
        this.colorpalets = [];
    }
    add(options) {
        options.list = new UIList(this.canvas)
        options.list.add({
            name: 'colors',
            x: options.x, y: options.y, width: options.width, height: options.height, scrollbarwidth: 30,
            elementOptions: {
                border: '#ffffff',
                hover_border: '#ffffff',
                border_width: 3,
                height: 35,
                width: 35,
                gap: 7,
                border_radius: 3,
                callback: options.callback
            }
        });
        options.colorList = [];
        options.values = [['#9C9C9C', '#000000'],
                          ['#FFA420', '#000000'],
                          ['#3B3C36', '#ffffff'],
                          ['#8E402A', '#ffffff'],
                          ['#317F43', '#000000'],
                          ['#4C9141', '#000000'],
                          ['#CB3234', '#000000'],
                          ['#4D5645', '#000000'],
                          ['#6A5D4D', '#000000'],
                          ['#A98307', '#000000'],
                          ['#2F353B', '#ffffff'],
                          ['#FF2301', '#ffffff'],
                          ['#7D7F7D', '#000000'],
                          ['#84C3BE', '#000000'],
                          ['#343E40', '#000000'],
                          ['#969992', '#000000'],
                          ['#3E5F8A', '#000000']] //background, foreground | Color Palet Values

        for (var i in options.values) {
            options.colorList.push({ background: [options.values[i][0]], foreground: options.values[i][1], callbackData: [options.values[i][0], options.values[i][1]] });
        }
        options.list.find('colors').setList(options.colorList)
        this.colorpalets.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            colorpalet.list.render(ctx);
        }
    }
    onClick(x, y) {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            colorpalet.list.onClick(x, y);
        }
        return;
    }
    onMouseDown(x, y) {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            colorpalet.list.onMouseDown(x, y);

        }
        return;
    }
    onMouseUp(x, y) {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            colorpalet.list.onMouseUp(x, y);

        }
        return;
    }
    onMouseMove(x, y) {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            colorpalet.list.onMouseMove(x, y);
        }
        return;
    }
    find(name) {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            if (colorpalet.name == name) {
                return colorpalet;
            }
        }
    }
    clear() {
        for (var i in this.colorpalets) {
            var colorpalet = this.colorpalets[i];
            colorpalet.list.clear();
        }
        this.colorpalets = [];
    }
}