class UIButtonRow {
    constructor(canvas) {
        this.canvas = canvas;
        this.buttonrows = [];
    }
    add(options) {
        options.button = new UIButton(this.canvas);
        options.edit_button = new UIButton(this.canvas);
        options.add_button = new UIButton(this.canvas);
        options.change_name = new UIDialog(this.canvas);
        options.editable = false;
        options.mouse_down_on = null;
        options.mouse_down_on_x = null;
        options.mouse_down_on_elements = [];
        options.inputDisabled = false;
        options.add_room = false;
        options.addButton = () => {
            options.add_button.clear();
            var x = options.x + (options.elementOptions.width + options.gap) * options.edit_button.buttons.length;
            var height = options.elementOptions.height;
            var y = options.y;
            var width = height;

            options.add_button.add({
                displaytext: '➕',
                background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', hover_border: '#32d600', border_width: 3, grd_type: 'vertical',
                x: x, y: y, width: width, height: height, border_radius: 10, font_size: 50,
                callback: () => {
                    options.change_name.add({
                        background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'room_name',
                        hover_border: '#32d600', border_width: 3, width: 700, height: 400, callback: options.dialogClose,
                        alpha_x: options.dialog_data.x, alpha_y: options.dialog_data.y, alpha_width: options.dialog_data.width, alpha_height: options.dialog_data.height,
                        type: 'textInput', displaytext: _trquote('Room Name'), text: ''
                    });
                    options.callback(true);
                    options.inputDisabled = true;
                    options.add_room = true;
                }
            });
        }

        options.roomSelected = (room) => {
            if (!options.editable) {
                for (var i in options.button.buttons) {
                    options.button.buttons[i].border = options.elementOptions.border;
                    options.button.buttons[i].border_width = options.elementOptions.border_width;
                    if (options.button.buttons[i].i == room) {
                        options.button.buttons[i].border = '#ffffff';
                        options.button.buttons[i].border_width = 3;
                    }
                }
            }
            else {
                for (var i in options.edit_button.buttons) {
                    options.edit_button.buttons[i].border = options.elementOptions.border;
                    options.edit_button.buttons[i].border_width = options.elementOptions.border_width;
                    if (options.edit_button.buttons[i].i == room) {
                        options.edit_button.buttons[i].border = '#ffffff';
                        options.edit_button.buttons[i].border_width = 3;
                    }
                }
            }
            options.roomSelectCallback(room);
            triggerRepaint();
        }
        options.changeColor = (color) => {
            options.edit_button.buttons[options.index].background = [color[0]];
            options.edit_button.buttons[options.index].foreground = color[1];
        }
        options.deleteRoomConformation = (call) => {
            if (call == 'ok') {
                options.edit_button.buttons.splice(options.index, 1);
                for (var i in options.edit_button.buttons) {
                    var button = options.edit_button.buttons[i];
                    button.x = options.x + (button.width + options.gap) * i;
                    button.y = options.y;
                }
                if (options.edit_button.buttons.length > 0) {
                    options.roomSelected(options.edit_button.buttons[0].i);
                } else {
                    options.roomSelected(0);
                }
                options.roomDeleteCallback(options.index);
                options.index = null;
                options.change_name.clear();
                options.addButton();
                options.inputDisabled = false;
                options.callback(false);
                triggerRepaint();
                return options.index;
            }
            else {
                options.change_name.clear();
                options.callback(false);
                options.inputDisabled = false;
                triggerRepaint();
            }
        }
        options.deleteRoom = () => {
            if (options.index !== null && options.index !== undefined) {
                options.inputDisabled = true;
                options.callback(true); //disable input of parent objects
                options.change_name.add({
                    background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'room_name',
                    hover_border: '#32d600', border_width: 3, width: 700, height: 400, callback: options.deleteRoomConformation,
                    alpha_x: options.dialog_data.x, alpha_y: options.dialog_data.y, alpha_width: options.dialog_data.width, alpha_height: options.dialog_data.height,
                    type: 'conformation', displaytext: 'Raum wirklich löschen?'
                });
            }
        }
        options.dialogClose = (action) => {
            if (action == 'ok') {
                var room_name = options.change_name.find('room_name').getText();
                var element_options = Object.assign({}, { displaytext: room_name, background: ['#0000FF'], foreground: '#FFFFFF' }, options.elementOptions);
                element_options.x = options.x + (element_options.width + options.gap) * options.edit_button.buttons.length;
                element_options.y = options.y;
                element_options.i = options.edit_button.buttons.length;
                element_options.callback = options.roomSelected;
                element_options.callbackData = element_options.i;
                options.edit_button.add(element_options);
                options.addButton();
                options.roomSelected(element_options.i);
                options.index = element_options.i;
            }
            options.callback(false);
            options.inputDisabled = false;
            options.change_name.clear();

        }
        options.getList = () => {
            var names = [];
            if (!options.editable) {
                for (var i in options.button.buttons) {
                    names.push({
                        displaytext: options.button.buttons[i].displaytext, i: options.button.buttons[i].i,
                        foreground: options.button.buttons[i].foreground, background: options.button.buttons[i].background
                    });
                }
            }
            else {
                for (var i in options.edit_button.buttons) {
                    names.push({
                        displaytext: options.edit_button.buttons[i].displaytext, i: options.edit_button.buttons[i].i,
                        foreground: options.edit_button.buttons[i].foreground, background: options.edit_button.buttons[i].background
                    });
                }
            }
            return names;
        }
        options.setList = (elements) => {
            for (var i in elements) {
                var element = elements[i];
                var element_options = Object.assign({}, element, options.elementOptions);
                element_options.callback = options.roomSelected;
                element_options.callbackData = i;
                element_options.x = options.x + (element_options.width + options.gap) * i;
                element_options.y = options.y;
                element_options.i = i;
                if (!options.editable) {
                    options.button.add(element_options);
                }
                else {
                    options.edit_button.add(element_options);
                }
            }
            triggerRepaint();
        };
        options.edit = () => {
            if (!options.editable) {
                for (var i in options.button.buttons) {
                    options.edit_button.add(options.button.buttons[i]);
                }
                options.button.clear();
            }
            options.editable = true;
            options.addButton();
            triggerRepaint();
        };
        options.stopEdit = (action) => {
            if (options.editable) {
                if (action == 'save') {
                    for (var i in options.edit_button.buttons) {
                        options.button.add(options.edit_button.buttons[i]);
                    }
                }
                options.edit_button.clear();
                options.add_button.clear();
                options.change_name.clear();
            }
            options.index = null;
            options.editable = false;
        }
        options.renameDialogClose = (action) => {
            if (action == 'ok') {
                var room_name = options.change_name.find('room_name').getText();
                options.edit_button.buttons[options.index].displaytext = room_name;
            }
            options.callback(false);
            options.inputDisabled = false;
            options.change_name.clear();

        }
        options.renameRoom = () => {
            console.log('Rename Rooom')
            options.change_name.add({
                background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'room_name',
                hover_border: '#32d600', border_width: 3, width: 700, height: 400, callback: options.renameDialogClose,
                alpha_x: options.dialog_data.x, alpha_y: options.dialog_data.y, alpha_width: options.dialog_data.width, alpha_height: options.dialog_data.height,
                type: 'textInput', displaytext: _trquote('Room Name'), text: options.edit_button.buttons[options.index].displaytext
            });
            options.callback(true);
            options.inputDisabled = true;
            options.add_room = true;
        }
        this.buttonrows.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            if (buttonrow.editable == true) {
                for (var j in buttonrow.edit_button.buttons) {
                    var button = buttonrow.edit_button.buttons[j];
                    if (buttonrow.index == j) {
                        ctx.lineWidth = 2;
                        ctx.strokeStyle = '#FF0000';
                        ctx.strokeRect(button.x - 5, button.y - 5, button.width + 10, button.height + 10);

                    }
                }
            }
            buttonrow.button.render(ctx);
            buttonrow.edit_button.render(ctx);
            buttonrow.add_button.render(ctx);
            buttonrow.change_name.render(ctx);


        }
    }
    onClick(x, y) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            if (!buttonrow.inputDisabled) {
                buttonrow.button.onClick(x, y);
                buttonrow.edit_button.onClick(x, y);
                buttonrow.add_button.onClick(x, y);
            }
            buttonrow.change_name.onClick(x, y);

        }
    }
    onMouseDown(x, y) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            buttonrow.change_name.onMouseDown(x, y);
            if (!buttonrow.inputDisabled) {
                buttonrow.button.onMouseDown(x, y);
                buttonrow.edit_button.onMouseDown(x, y);
                buttonrow.add_button.onMouseDown(x, y);
                if (buttonrow.editable) {
                    for (var j in buttonrow.edit_button.buttons) {
                        var edit_button = buttonrow.edit_button.buttons[j];
                        var startx = edit_button.x;
                        var starty = edit_button.y;
                        var endx = startx + edit_button.width;
                        var endy = starty + edit_button.height;
                        if (x >= startx && x <= endx && y >= starty && y <= endy) {
                            buttonrow.index = j;
                            buttonrow.roomSelected(buttonrow.edit_button.buttons[j].i); //select room 
                            buttonrow.mouse_down_on = j;
                            buttonrow.mouse_down_on_x = x - startx;
                            buttonrow.mouse_down_on_elements = [...buttonrow.edit_button.buttons];
                            triggerRepaint();
                            return;
                        }
                        startx = buttonrow.contain_x;//contain aria mousedown unselects room 
                        starty = buttonrow.contain_y;
                        endx = startx + buttonrow.contain_width;
                        endy = starty + buttonrow.contain_height;
                        if (x >= startx && x <= endx && y >= starty && y <= endy) {
                            buttonrow.index = null;
                            triggerRepaint();
                        }
                    }
                }
            }

        }
    }
    onMouseUp(x, y) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            buttonrow.change_name.onMouseUp(x, y);
            if (!buttonrow.inputDisabled) {
                buttonrow.button.onMouseUp(x, y);
                buttonrow.edit_button.onMouseUp(x, y);
                buttonrow.add_button.onMouseUp(x, y);
            }
            buttonrow.mouse_down_on = null;
            buttonrow.mouse_down_on_x = null;
            buttonrow.mouse_down_on_elements = null;
        }
    }
    moveItem(arr, itemIndex, targetIndex) {
        let itemRemoved = arr.splice(itemIndex, 1); // splice() returns the remove element as an array
        arr.splice(targetIndex, 0, itemRemoved[0]); // Insert itemRemoved into the target index
        return arr;
    }

    onMouseMove(x, y) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            buttonrow.change_name.onMouseMove(x, y);
            if (!buttonrow.inputDisabled) {
                buttonrow.button.onMouseMove(x, y);
                buttonrow.edit_button.onMouseMove(x, y);
                buttonrow.add_button.onMouseMove(x, y);
                if (buttonrow.mouse_down_on) {
                    //calculate index when moving
                    var index = (x - buttonrow.x) / (buttonrow.mouse_down_on_elements[0].width + buttonrow.gap);
                    if (index > 0) {
                        if (index >= buttonrow.mouse_down_on_elements.length) {
                            index = buttonrow.mouse_down_on_elements.length - 1;
                        }
                        buttonrow.index = Math.floor(index);
                        var arr = this.moveItem([...buttonrow.mouse_down_on_elements], buttonrow.mouse_down_on, index);
                        buttonrow.edit_button.buttons = arr;
                        for (var j in arr) {
                            buttonrow.edit_button.buttons[j].x = buttonrow.x + (buttonrow.mouse_down_on_elements[0].width + buttonrow.gap) * j;
                            if (Math.floor(index) != buttonrow.mouse_down_on) {
                                buttonrow.edit_button.mouse_down_on = null;
                            }
                        }
                        triggerRepaint();
                    }
                }
            }
        }
    }
    onKeyDown(e) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            buttonrow.change_name.onKeyDown(e);

        }
    }
    onKeyUp(e) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            buttonrow.change_name.onKeyUp(e);
        }
    }
    find(name) {
        for (var i in this.buttonrows) {
            var buttonrow = this.buttonrows[i];
            if (buttonrow.name == name) {
                return buttonrow;
            }

        }
    }
}