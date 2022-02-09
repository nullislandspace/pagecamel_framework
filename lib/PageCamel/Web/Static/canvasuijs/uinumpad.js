class UINumpad {
    constructor() {
        this.button = new UIButton();
        this.numpads = [];
    }

    add(options) {
        this.numpads.push(options);
        //addButtonGroup(x, y, width, height, gap, buttontexts, keyvalues, textcolor, buttoncolor, callback, callbackData, roundCorner) {


        var keyvalues = [['+/-', 'ZWS', 'BS'], ['7', '8', '9'], ['4', '5', '6'], ['1', '2', '3'], ['x', '0', ',']];
        if (!options.show_keys.x) {
            keyvalues[4][0] = null;
        }
        if (!options.show_keys.ZWS) {
            keyvalues[0][1] = null;
        }

        var button_height = options.height / keyvalues.length - options.gap; //change
        var button_width = options.width / keyvalues[0].length - options.gap;
        for (var buttons_y = 0; buttons_y < keyvalues.length; buttons_y++) {
            var position_y = options.y + (button_height + options.gap) * buttons_y;
            for (var buttons_x = 0; buttons_x < keyvalues[0].length; buttons_x++) {
                if (keyvalues[buttons_y][buttons_x] != null) {
                    var position_x = options.x + (button_width + options.gap) * buttons_x;
                    var button = {
                        displaytext: keyvalues[buttons_y][buttons_x],
                        x: position_x, y: position_y, width: button_width, height: button_height,
                        type: 'Button',
                        callbackData: { key: options.callbackData.key, value: keyvalues[buttons_y][buttons_x] }
                    };
                    this.button.add(Object.assign({}, options, button));
                }
            }
        }
        return options;
    }

    render(ctx) {
        this.button.render(ctx);
    }

    onClick(x, y) {
        this.button.onClick(x, y);
    }
    onHover(x ,y) {
        this.button.onHover(x, y)
    }
}