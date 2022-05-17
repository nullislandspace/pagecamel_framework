class UINumpad {
    constructor(canvas) {
        this.button = new UIButton();
        this.numpads = [];
    }

    add(options) {
        this.numpads.push(options);
        //addButtonGroup(x, y, width, height, gap, buttontexts, keyvalues, textcolor, buttoncolor, callback, callbackData, roundCorner) {


        var keyvalues = [
            [{ text: _trquote('+/-') }, { text: _trquote('ZWS') }, { text: _trquote('⌫'), keyCode: [8] }],
            [{ text: _trquote('7'), keyCode: [103, 55] }, { text: _trquote('8'), keyCode: [104, 56] }, { text: _trquote('9'), keyCode: [57, 105] }],
            [{ text: _trquote('4'), keyCode: [100, 52] }, { text: _trquote('5'), keyCode: [101, 53] }, { text: _trquote('6'), keyCode: [102, 54] }],
            [{ text: _trquote('1'), keyCode: [97, 49] }, { text: _trquote('2'), keyCode: [98, 50] }, { text: _trquote('3'), keyCode: [99, 51] }],
            [{ text: _trquote('x'), keyCode: [106] }, { text: _trquote('0'), keyCode: [96, 48] }, { text: _trquote(','), keyCode: [108, 188] }]];
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
                    var keyCode = undefined;
                    if (options.allow_keyboard) {
                        keyCode = keyvalues[buttons_y][buttons_x].keyCode;
                    }
                    if (options.callbackData !== undefined) {
                        var button = {
                            displaytext: keyvalues[buttons_y][buttons_x].text,
                            accept_keycode: keyCode,
                            x: position_x, y: position_y, width: button_width, height: button_height,
                            type: 'Button',
                            callbackData: { key: options.callbackData.key, value: keyvalues[buttons_y][buttons_x].text }
                        };
                    }
                    else {
                        var button = {
                            displaytext: keyvalues[buttons_y][buttons_x].text,
                            accept_keycode: keyCode,
                            x: position_x, y: position_y, width: button_width, height: button_height,
                            type: 'Button',
                            callbackData: { value: keyvalues[buttons_y][buttons_x].text }
                        };
                    }
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
    onMouseDown(x, y) {
        this.button.onMouseDown(x, y);
    }
    onMouseUp(x, y) {
        this.button.onMouseUp(x, y);
    }
    onMouseMove(x, y) {
        this.button.onMouseMove(x, y);
    }
    onKeyDown(e) {
        this.button.onKeyDown(e);
    }
    find(name) {
        return;
    }
    clear() {
        this.numpads = [];
        this.button.clear();
    }
}