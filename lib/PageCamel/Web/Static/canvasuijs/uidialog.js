class UIDialog {
    constructor(canvas) {
        this.pressed_char = new GetPressedKeyChar();
        this.dialogs = [];
        this.canvas = canvas;
    }
    add(options) {
        options.button = new UIButton(this.canvas);
        options.textinput = new UITextInput(this.canvas);
        options.list = new UIScrollList(this.canvas);
        options.title = new UIText();
        options.active = true;
        options.setList = (data) => {
            if (options.type == 'select') {
                options.list.find('menuList').setList(data);
            }
        }
        options.getList = () => {
            if (options.type === 'select') {
                return options.textinput.find('menuList').getList();
            }
        }
        options.getSelectedItemIndex = () => {
            if (options.type == 'select') {
                return options.list.find('menuList').getSelectedItemIndex();
            }
        }
        options.getText = () => {
            if (options.type === 'textInput') {
                options.textinput.find('room_name').getText();
            }
        }
        options.action = (call) => {
            options.callback(call)
        }
        if (options.type != 'alert') {
            options.button.add({
                displaytext: '🗙 Abbrechen',
                accept_keycode: [27],
                background: ['#ff948c', '#ff1100',], foreground: '#000000', border: '#ff948c', border_width: options.border_width, grd_type: 'vertical',
                x: options.alpha_x + options.alpha_width / 2 + options.width / 2 - 155, y: options.alpha_y + options.alpha_height / 2 + options.height / 2 - 50,
                width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#ff1100',
                callback: options.action,
                callbackData: 'cancel'
            });
            options.button.add({
                displaytext: '✓ OK',
                accept_keycode: [13],
                background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', hover_border: '#32d600', border_width: 3, grd_type: 'vertical',
                x: options.alpha_x + options.alpha_width / 2 + options.width / 2 - 270, y: options.alpha_y + options.alpha_height / 2 + options.height / 2 - 50, width: 100, height: 45, border_radius: 20, font_size: 18,
                callback: options.action,
                callbackData: 'ok'
            });
        }
        else {
            options.button.add({
                displaytext: '✓ OK',
                accept_keycode: [13],
                background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', hover_border: '#32d600', border_width: 3, grd_type: 'vertical',
                x: options.alpha_x + options.alpha_width / 2 + options.width / 2 - 105, y: options.alpha_y + options.alpha_height / 2 + options.height / 2 - 50, width: 100, height: 45, border_radius: 20, font_size: 18,
                callback: options.action,
                callbackData: 'ok'
            });
        }
        if (options.type === 'textInput') {
            options.textinput.add({
                displaytext: options.text, name: 'room_name',
                background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                x: options.alpha_x + options.alpha_width / 2 - 100, y: options.alpha_y + options.alpha_height / 2 - 25, width: 200, height: 50, font_size: 30, align: 'left'
            });
            options.title.add({
                displaytext: options.displaytext,
                foreground: '#000000',
                x: options.alpha_x + options.alpha_width / 2 - 100, y: options.alpha_y + options.alpha_height / 2 - 50,
                font_size: 30
            });
        }
        if (options.type === 'conformation' || options.type === 'alert') {
            options.title.add({
                displaytext: options.displaytext,
                foreground: '#000000',
                x: options.alpha_x + options.alpha_width / 2 - 100, y: options.alpha_y + options.alpha_height / 2 - 55,
                font_size: 30
            });
        }
        if (options.type === 'select') {
            options.title.add({
                displaytext: options.displaytext,
                foreground: '#000000',
                x: options.alpha_x + options.alpha_width / 2 - options.width / 2 + 20,
                y: options.alpha_y + options.alpha_height / 2 - options.height / 2 + 20,
                font_size: 30,
            });
            options.list.add(
                {
                    name: 'menuList',
                    background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                    x: options.alpha_x + options.alpha_width / 2 - options.width / 2 + 20,
                    y: options.alpha_y + options.alpha_height / 2 - options.height / 2 + 40,
                    width: options.width - 40, height: options.height - 120, scrollbarwidth: 30,
                    scrollbarbackground: '#A9A9A9', hover_border: '#A9A9A9',
                    pagescrollbuttonheight: 35,
                    elementOptions: {
                        selectedBackground: '#00ffff',
                        height: 30,
                        font_size: 25,
                    }
                });
        }
        options.getText = () => {
            return options.textinput.find('room_name').getText();
        }
        this.dialogs.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            ctx.fillStyle = '#636363d8';
            ctx.fillRect(dialog.alpha_x, dialog.alpha_y, dialog.alpha_width, dialog.alpha_height);
            ctx.fillStyle = dialog.background[0];
            ctx.fillRect(dialog.alpha_x + dialog.alpha_width / 2 - dialog.width / 2, dialog.alpha_y + dialog.alpha_height / 2 - dialog.height / 2, dialog.width, dialog.height);
            ctx.fillStyle = dialog.foreground;
            ctx.fillRect(dialog.alpha_x + dialog.alpha_width / 2 - dialog.width / 2, dialog.alpha_y + dialog.alpha_height / 2 + dialog.height / 2 - 55, dialog.width, 55);
            dialog.button.render(ctx);
            dialog.textinput.render(ctx);
            dialog.title.render(ctx);
            dialog.list.render(ctx);
        }
    }
    onClick(x, y) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            dialog.button.onClick(x, y);
            dialog.textinput.onClick(x, y);
            dialog.list.onClick(x, y);
        }
    }
    onMouseDown(x, y) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            dialog.button.onMouseDown(x, y);
            dialog.textinput.onMouseDown(x, y);
            dialog.list.onMouseDown(x, y);

        }
    }
    onMouseUp(x, y) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            dialog.button.onMouseUp(x, y);
            dialog.textinput.onMouseUp(x, y);
            dialog.list.onMouseUp(x, y);
        }
    }
    onMouseMove(x, y) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            dialog.button.onMouseMove(x, y);
            dialog.textinput.onMouseMove(x, y);
            dialog.list.onMouseMove(x, y);
        }
    }
    onKeyDown(e) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            dialog.button.onKeyDown(e);
            dialog.textinput.onKeyDown(e);
        }


    }
    onKeyUp(e) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            dialog.textinput.onKeyUp(e);
        }
    }
    find(name) {
        for (var i in this.dialogs) {
            var dialog = this.dialogs[i];
            if (dialog.name == name) {
                return dialog;
            }
        }
    }
    clear() {
        this.dialogs = [];
    }
}
