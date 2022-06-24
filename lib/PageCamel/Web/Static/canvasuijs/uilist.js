class UIList {
    //UI List Element
    constructor(canvas) {
        this.lists = [];
    }
    add(options) {
        options.button = new UIButton();
        options.arrowbutton = new UIArrowButton();
        options.edit = false;
        options.items = [];
        options.mouse_down_on = null;
        if (options.scrollbarwidth === undefined) {
            options.scrollbarwidth = 50;
        }
        options.setList = (params) => {
            options.items = params;
            options.scrollPosition = 0;
            this.createList();
        }
        options.edit = (state) => {
            if (state) {
                options.editmode = true;
            }
        }
        options.getList = () => {
            return options.items;
        }
        options.decreaseScrollPosition = (params) => {
            options.scrollPosition -= 1;
            this.createList();
        }
        options.increaseScrollPosition = (params) => {
            options.scrollPosition += 1;
            this.createList();
        }
        options.showUpArrow = false;
        options.showDownArrow = false;
        this.lists.push(options);
        return options
    }
    createList() {
        for (var i in this.lists) {
            var list = this.lists[i];
            list.button.clear();
            list.arrowbutton.clear();
            var max_y_buttons = Math.round(list.height / (list.elementOptions.height + list.elementOptions.gap) - 0.49);
            var max_x_buttons = Math.round((list.width - list.scrollbarwidth) / (list.elementOptions.width + list.elementOptions.gap) - 0.49);
            for (var j in list.items) {
                var button_x;
                var button_y;
                var item = list.items[j];
                var button = { ...item, ...list.elementOptions };//elementOptions = Button Options
                var max_buttons = max_x_buttons * max_y_buttons;//max buttons per page
                var item_index = j - max_buttons * list.scrollPosition;
                var [x, y] = this.getItemPosition(max_x_buttons, item_index);
                if (y < max_y_buttons && y >= 0) { //Check if button is on this page
                    button_x = list.x + x * (button.width + button.gap);
                    button_y = list.y + y * (button.height + button.gap);
                    button.x = button_x;
                    button.y = button_y;
                    list.button.add(button);
                }
            }
            //scrollbutton Down
            if (list.items.length > 0) {
                if (max_buttons * (list.scrollPosition + 1) < list.items.length) {
                    var scroll_x = list.x + list.width - list.scrollbarwidth;
                    var scroll_y = list.y + list.height - list.scrollbarwidth;
                    list.arrowbutton.add({
                        x: scroll_x, y: scroll_y, width: list.scrollbarwidth, height: list.scrollbarwidth, direction: 'down',
                        background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
                        callback: list.increaseScrollPosition
                    });
                }
                //scrollbutton Up
                if (list.scrollPosition != 0) {
                    var scroll_x = list.x + list.width - list.scrollbarwidth;
                    var scroll_y = list.y;
                    list.arrowbutton.add({
                        x: scroll_x, y: scroll_y, width: list.scrollbarwidth, height: list.scrollbarwidth, direction: 'up',
                        background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
                        callback: list.decreaseScrollPosition
                    });
                }
            }
        }


    }
    getItemPosition(max_x_buttons, item_index) {
        var x = (item_index % max_x_buttons)
        var y = Math.round((item_index / max_x_buttons) - 0.49);
        return [x, y];
    }
    render(ctx) {
        //loop through all lists
        for (var i in this.lists) {
            var list = this.lists[i];
            list.button.render(ctx);
            list.arrowbutton.render(ctx);
        }
    }
    onClick(x, y) {
        for (var i in this.lists) {
            var list = this.lists[i];
            list.button.onClick(x, y);
            list.arrowbutton.onClick(x, y);
        }
    }
    onMouseDown(x, y) {
        for (var i in this.lists) {
            var list = this.lists[i];
            list.button.onMouseDown(x, y);
            list.arrowbutton.onMouseDown(x, y);
            // assign item index where mouse down to mouse_down_on
            for (var j in list.button.buttons) {
                var button = list.button.buttons[j];
                if (button.x <= x && button.x + button.width >= x && button.y <= y && button.y + button.height >= y) {
                    list.mouse_down_on = j;
                }
                if (j + 1 == list.button.buttons.length) {
                    list.mouse_down_on = null;
                }
            }

        }
    }
    onMouseUp(x, y) {
        for (var i in this.lists) {
            var list = this.lists[i];
            list.button.onMouseUp(x, y);
            list.arrowbutton.onMouseUp(x, y);
            list.mouse_down_on = null;
        }
    }
    getButtonUnderMouse(x, y) {
        for (var i in this.lists) {
            var list = this.lists[i];
            for (var j in list.button.buttons) {
                var button = list.button.buttons[j];
                if (button.x <= x && button.x + button.width >= x && button.y <= y && button.y + button.height >= y) {
                    return button;
                }
            }
        }
        return null;
    }
    onMouseMove(x, y) {
        for (var i in this.lists) {
            var list = this.lists[i];
            list.button.onMouseMove(x, y);
            list.arrowbutton.onMouseMove(x, y);
            // if mouse down on item
            if (list.mouse_down_on != null && list.editmode) {
                console.log('mouse down on item:', list.mouse_down_on);

            }

        }
    }
    find(name) {
        for (var i in this.lists) {
            var list = this.lists[i];
            if (list.name == name) {
                return list;
            }
        }
    }
    clear() {
        this.lists = []
    }

}
canvasuijs.addType('List', UIList);
