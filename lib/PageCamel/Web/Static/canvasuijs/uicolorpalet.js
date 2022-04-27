class UIColorPalet {
    constructor(canvas) {
        this.canvas = canvas
        this.colorpalets = [];
    }
    add(options) {
        options.list = new UIList(this.canvas)
        options.list.add({
            name: 'colors',
            x: options.x, y: options.y, width: options.width, height: options.height - 10, scrollbarwidth: 30,
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
        options.values = this.generateColorPalet(4);
        for (var i in options.values) {
            options.colorList.push({ background: [options.values[i][0]], foreground: options.values[i][1], callbackData: [options.values[i][0], options.values[i][1]] });
        }
        options.list.find('colors').setList(options.colorList)
        this.colorpalets.push(options);
        return options;
    }

    generateColorPalet(color_count) {
        var multiplier = 255 / (color_count - 1)
        var combined = [];
        for (var red = 0; red < color_count; red++) {
            for (var green = 0; green < color_count; green++) {
                for (var blue = 0; blue < color_count; blue++) {
                    var color = [red * multiplier, green * multiplier, blue * multiplier];
                    var foreground = (color[0] + color[1] + color[2]) / 3
                    if (foreground > 128) {
                        foreground = 0;
                    }
                    else {
                        foreground = 255
                    }
                    var hex_background = '#' + RGBToHex(color[0], color[1], color[2]);
                    var hex_foreground = '#' + RGBToHex(foreground, foreground, foreground);
                    combined.push([hex_background, hex_foreground]);
                }
            }
        }
        return combined;

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