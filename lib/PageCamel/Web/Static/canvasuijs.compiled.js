class UIView {
    constructor(canvas) {
        this.is_active = false;
        this.canvas = canvas;
        this.ctx = document.getElementById(this.canvas).getContext('2d');

        this.button = new UIButton();
        this.line = new UILine();
        this.text = new UIText();
        this.numpad = new UINumpad();
        this.list = new UIList();
        this.arrowbutton = new UIArrowButton();
        this.textbox = new UITextBox();
        this.paylist = new UIPayList();
        this.dragndrop = new UIDragNDrop();
        this.ui_types = [
            { type: 'Button', object: this.button },
            { type: 'Line', object: this.line },
            { type: 'Text', object: this.text },
            { type: 'Numpad', object: this.numpad },
            { type: 'List', object: this.list },
            { type: 'ArrowButton', object: this.arrowbutton },
            { type: 'TextBox', object: this.textbox },
            { type: 'PayList', object: this.paylist },
            { type: 'DragNDrop', object: this.dragndrop}
        ];//Change when adding new UI Type

        this.onClick = this.onClick.bind(this);
        this.onMouseUp = this.onMouseUp.bind(this);
        this.onMouseDown = this.onMouseDown.bind(this);
        this.onMouseMove = this.onMouseMove.bind(this);
        
        $('#' + this.canvas).on('mousedown', this.onMouseDown);
        $('#' + this.canvas).on('mouseup', this.onMouseUp);
        $('#' + this.canvas).on('click', this.onClick);
        $('#' + this.canvas).on('mouseleave', this.onMouseUp);
        $('#' + this.canvas).on('mousemove', this.onMouseMove);
        /*this.d_options = {
            background-color: #...
        }*/
    }
    element(name) {
        for (var i in this.ui_types) {
            var obj = this.ui_types[i].object.find(name);
            if (obj != null) {
                return obj;
            }
        }
    }
    addElement(element_type, options) {
        for (var i in this.ui_types) {
            if (this.ui_types[i].type == element_type) {
                options.type = element_type;
                this.ui_types[i].object.add(options);
                return this.ui_types[i].object;
            }
        }
    }

    render() {
        if (this.is_active) {
            for (let i in this.ui_types) {
                this.ui_types[i].object.render(this.ctx);
            }
        }
        else {
            return;
        }
    }
    setActive(state) {
        this.is_active = state;

    }
    onClick(e) {
        if (this.is_active == true) {
            var canvas = $('#' + this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onClick(x, y);
            }
        } else {
            return;
        }
    }
    onMouseUp(e) {
        if (this.is_active == true) {
            var canvas = $('#' + this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onMouseUp(x, y);
            }
        } else {
            return;
        }
    }
    onMouseDown(e) {
        if (this.is_active == true) {
            var canvas = $('#' + this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onMouseDown(x, y);
            }
        } else {
            return;
        }
    }
    onMouseMove(e) {
        if (this.is_active == true) {
            var canvas = $('#' + this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onMouseMove(x, y);
            }
        } else {
            return;
        }
    }

}class UIText {
    constructor() {
        this.texts = [];
    }
    add(options) {
        this.texts.push(options);
        return options;
    }
    render(ctx) {
        for (let i in this.texts) {
            let text = this.texts[i];
            ctx.font = text.font_size + 'px Courier'
            ctx.fillStyle = text.foreground;
            if (!text.displaytext.includes("\n")) {
                ctx.fillText(text.displaytext, text.x, text.y + text.font_size /1.7);
            } else {
                var blines = text.displaytext.split("\n");
                var yoffs = text.y + text.font_size /1.7;
                var j;
                for (j = 0; j < blines.length; j++) {
                    blines[j].replace("\n", '');
                    ctx.fillText(blines[j], text.x, yoffs);
                    yoffs += text.font_size;
                }
            }
        }
    }
    onClick(x, y) {
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
}class UIButton {
    constructor() {
        this.hovering_on = null;
        this.buttons = [];
        this.mouse_down_on = null;
    }
    add(options) {
        this.buttons.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            ctx.font = button.font_size + 'px Courier';
            if (i == this.hovering_on) {
                ctx.strokeStyle = button.hover_border;
            }
            else {
                ctx.strokeStyle = button.border;
            }
            var grd;
            if (button.grd_type == 'horizontal') {
                grd = ctx.createLinearGradient(button.x, button.y, button.x + button.width, button.y);
            }
            else if (button.grd_type == 'vertical') {
                grd = ctx.createLinearGradient(button.x, button.y, button.x, button.y + button.height);
            }
            if (button.grd_type) {
                var step_size = 1 / button.background.length;
                if (i == this.mouse_down_on) {
                    ctx.fillStyle = button.background[button.background.length - 1];
                }
                else {
                    for (var j in button.background) {
                        grd.addColorStop(step_size * j, button.background[j]);
                        ctx.fillStyle = grd;
                    }
                }
            }
            if (button.background.length == 1) {
                ctx.fillStyle = button.background[0];
            }
            if (!button.border_radius) {
                ctx.fillRect(button.x, button.y, button.width, button.height);
                ctx.strokeRect(button.x, button.y, button.width, button.height);
            } else {
                roundRect(ctx, button.x, button.y, button.width, button.height, button.border_radius, button.border_width);
            }
            ctx.fillStyle = button.foreground;
            ctx.strokeStyle = button.foreground;
            if (button.displaytext) {
                if (!button.displaytext.includes("\n")) {
                    ctx.fillText(button.displaytext, button.x + 8, button.y + (button.height / 2));
                } else {
                    var blines = button.displaytext.split("\n");
                    var yoffs = button.y + ((button.height / 2) - (9 * (blines.length - 1)));
                    var j;
                    for (j = 0; j < blines.length; j++) {
                        blines[j].replace("\n", '');
                        ctx.fillText(blines[j], button.x + 8, yoffs);
                        yoffs = yoffs + 18;
                    }
                }
            }
        }
    }
    onClick(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button) {
                var startx = button.x;
                var starty = button.y;
                var endx = startx + button.width;
                var endy = starty + button.height;
                if (x >= startx && x <= endx && y >= starty && y <= endy) {
                    button.callback(button.callbackData);
                }
            }
        }
    }
    onMouseDown(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            var startx = button.x;
            var starty = button.y;
            var endx = startx + button.width;
            var endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                this.mouse_down_on = i;
                return;
            }
        }
        return;
    }
    onMouseUp(x, y) {
        this.mouse_down_on = null;
    }
    onMouseMove(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            var startx = button.x;
            var starty = button.y;
            var endx = startx + button.width;
            var endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                this.hovering_on = i;
                return;
            }
        }
        this.hovering_on = null;
        return;
    }
    find(name) {
        return;
    }
    clear() {
        this.mouse_down_on = null;
        this.hovering_on = null;
        this.buttons = [];
    }
}function roundRect(ctx, x, y, w, h, radius, line_width) {
    var r = x + w;
    var b = y + h;
    ctx.lineWidth = line_width;
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(r - radius, y);
    ctx.quadraticCurveTo(r, y, r, y + radius);
    ctx.lineTo(r, y + h - radius);
    ctx.quadraticCurveTo(r, b, r - radius, b);
    ctx.lineTo(x + radius, b);
    ctx.quadraticCurveTo(x, b, x, b - radius);
    ctx.lineTo(x, y + radius);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.fill();
    ctx.stroke();
}

class UILine {
    constructor() {
        this.lines = [];
    }
    add(options) {
        this.lines.push(options);
        return options;
    }
    render(ctx) {
        for(let i in this.lines) {
            let line = this.lines[i];
            ctx.strokeStyle = line.background;
            ctx.lineWidth = line.thickness;
            let x = line.x;
            let y = line.y;
            let endx = x + line.width;
            let endy = y + line.height
            ctx.beginPath();
            ctx.moveTo(x, y);
            ctx.lineTo(endx, endy);
            ctx.stroke();
        }
    }
    onClick(x,y){
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
    find(name){
        return;
    }
}class UIList {
    constructor() {
        this.lists = []
        this.button = new UIButton();
        this.arrowbutton = new UIArrowButton();
    }
    add(options) {
        options.setList = (params) => {
            options.articles = params;
            options.scrollPosition = 0;
            this.createList();
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
        this.button.clear();
        this.arrowbutton.clear();
        for (var i in this.lists) {
            var list = this.lists[i];
            var max_y_buttons = Math.round(list.height / (list.elementOptions.height + list.elementOptions.gap) - 0.49);
            var max_x_buttons = Math.round((list.width - list.scrollbarwidth) / (list.elementOptions.width + list.elementOptions.gap) - 0.49);
            for (var j in list.articles) {
                var button_x;
                var button_y;
                var article = list.articles[j];
                var button = { ...article, ...list.elementOptions };//elementOptions = Button Options
                var max_buttons = max_x_buttons * max_y_buttons;//max buttons per page
                var article_index = j - max_buttons * list.scrollPosition;
                var [x, y] = this.getArticlePosition(max_x_buttons, article_index);
                if (y < max_y_buttons && y >= 0) { //Check if button is on this page
                    button_x = list.x + x * (button.width + button.gap);
                    button_y = list.y + y * (button.height + button.gap);
                    button.x = button_x;
                    button.y = button_y;
                    this.button.add(button);
                }
            }
            if (max_buttons * (list.scrollPosition + 1) < list.articles.length) {
                var scroll_x = list.x + list.width - list.scrollbarwidth;
                var scroll_y = list.y + list.height - list.scrollbarwidth;
                this.arrowbutton.add({
                    x: scroll_x, y: scroll_y, width: list.scrollbarwidth, height: list.scrollbarwidth, direction: 'down',
                    background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
                    callback: list.increaseScrollPosition
                });
            }
            //scrollbutton Up
            if (list.scrollPosition != 0) {
                var scroll_x = list.x + list.width - list.scrollbarwidth;
                var scroll_y = list.y;
                this.arrowbutton.add({
                    x: scroll_x, y: scroll_y, width: list.scrollbarwidth, height: list.scrollbarwidth, direction: 'up',
                    background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
                    callback: list.decreaseScrollPosition
                });
            }
        }
        //scrollbutton Down


    }
    getArticlePosition(max_x_buttons, article_index) {
        var x = (article_index % max_x_buttons)
        var y = Math.round((article_index / max_x_buttons) - 0.49);
        return [x, y];
    }
    render(ctx) {
        this.button.render(ctx);
        this.arrowbutton.render(ctx);
    }
    onClick(x, y) {
        this.button.onClick(x, y);
        this.arrowbutton.onClick(x, y);

    }
    onMouseDown(x, y) {
        this.button.onMouseDown(x, y);
        this.arrowbutton.onMouseDown(x, y);
    }
    onMouseUp(x, y) {
        this.button.onMouseUp(x, y);
        this.arrowbutton.onMouseUp(x, y);
    }
    onMouseMove(x, y) {
        this.button.onMouseMove(x, y);
        this.arrowbutton.onMouseMove(x, y);
    }
    find(name) {
        for (var i in this.lists) {
            var list = this.lists[i];
            if (list.name == name) {
                return list;
            }
        }
    }

}class UINumpad {
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
    onMouseDown(x, y) {
        this.button.onMouseDown(x, y);
    }
    onMouseUp(x, y) {
        this.button.onMouseUp(x, y);
    }
    onMouseMove(x, y) {
        this.button.onMouseMove(x, y);
    }
    find(name) {
        return;
    }
}class UIArrowButton {
    constructor() {
        this.arrowbuttons = [];
        this.button = new UIButton();
    }
    add(options) {
        //this.arrowbuttons.push(options);
        var point1_x;
        var point1_y;
        var point2_x;
        var point2_y;
        var point3_x;
        var point3_y;
        if (options.direction == 'down') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.height;
            point2_y = 0;
            point3_x = options.height / 2;
            point3_y = options.height;
        } else if (options.direction == 'up') {
            point1_x = 0;
            point1_y = options.height;
            point2_x = options.height;
            point2_y = options.height;
            point3_x = options.height / 2;
            point3_y = 0;
        } else if (direction == 'right') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.height;
            point2_y = options.height / 2;
            point3_x = 0;
            point3_y = options.height;
        } else if (direction == 'left') {
            point1_x = options.height;
            point1_y = 0;
            point2_x = options.height;
            point2_y = options.height;
            point3_x = 0;
            point3_y = options.height / 2;
        }
        this.arrowbuttons.push({
            point1_x: point1_x,
            point1_y: point1_y,
            point2_x: point2_x,
            point2_y: point2_y,
            point3_x: point3_x,
            point3_y: point3_y,
            x: options.x,
            y: options.y,
            a_x: options.x + options.width / 2 - options.height / 2, // place arrow in center of button
        })
        this.button.add(options);
        return options;
    }
    render(ctx) {
        this.button.render(ctx);
        for (var i in this.arrowbuttons) {
            var arrowbutton = this.arrowbuttons[i];
            ctx.beginPath();
            ctx.moveTo(arrowbutton.a_x + arrowbutton.point1_x, arrowbutton.y + arrowbutton.point1_y);
            ctx.lineTo(arrowbutton.a_x + arrowbutton.point2_x, arrowbutton.y + arrowbutton.point2_y);
            ctx.lineTo(arrowbutton.a_x + arrowbutton.point3_x, arrowbutton.y + arrowbutton.point3_y);
            ctx.fill();

        }

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
    find(name) {
        return;
    }
    clear() {
        this.arrowbuttons = [];
        this.button.clear();
    }
}class UITextBox {
    constructor() {
        this.textboxes = [];
    }
    add(options) {
        options.setText = (params) => {
            options.displaytext = params;
        }
        this.textboxes.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.textboxes) {
            var textbox = this.textboxes[i];
            ctx.font = textbox.font_size + 'px Courier';
            ctx.strokeStyle = textbox.border;
            var grd;
            if (textbox.grd_type == 'horizontal') {
                grd = ctx.createLinearGradient(textbox.x, textbox.y, textbox.x + textbox.width, textbox.y);
            }
            else if (textbox.grd_type == 'vertical') {
                grd = ctx.createLinearGradient(textbox.x, textbox.y, textbox.x, textbox.y + textbox.height);
            }
            if (textbox.grd_type) {
                var step_size = 1 / textbox.background.length;

                for (var j in textbox.background) {
                    grd.addColorStop(step_size * j, textbox.background[j]);
                    ctx.fillStyle = grd;

                }
            }
            if (textbox.background.length == 1) {
                ctx.fillStyle = textbox.background[0];
            }
            if (!textbox.border_radius) {
                ctx.fillRect(textbox.x, textbox.y, textbox.width, textbox.height);
                ctx.strokeRect(textbox.x, textbox.y, textbox.width, textbox.height);
            } else {
                roundRect(ctx, textbox.x, textbox.y, textbox.width, textbox.height, textbox.border_radius, textbox.border_width);
            }
            ctx.fillStyle = textbox.foreground;
            ctx.strokeStyle = textbox.foreground;
            if (textbox.displaytext) {
                if (!textbox.displaytext.includes("\n")) {
                    if (textbox.align == 'right') {
                        var text_width = ctx.measureText(textbox.displaytext).width;
                        ctx.fillText(textbox.displaytext, textbox.x + textbox.width - text_width - 8, textbox.y + (textbox.height / 2) + textbox.font_size /3.3);
                    }
                    else {
                        ctx.fillText(textbox.displaytext, textbox.x + 8, textbox.y + (textbox.height / 2) + textbox.font_size /3.3);
                    }
                } else {
                    var blines = textbox.displaytext.split("\n");
                    var yoffs = textbox.y + ((textbox.height / 2) - (9 * (blines.length - 1)));
                    for (var j = 0; j < blines.length; j++) {
                        if (textbox.align == 'right') {
                            blines[j].replace("\n", '');
                            var text_width = ctx.measureText(blines[j]).width;
                            ctx.fillText(blines[j], textbox.x + textbox.width - text_width - 8, yoffs);
                        }
                        else {
                            blines[j].replace("\n", '');
                            ctx.fillText(blines[j], textbox.x + 8, yoffs);
                        }
                        yoffs = yoffs + 18;
                    }
                }
            }
        }
    }
    onClick(x, y) {
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
        for (var i in this.textboxes) {
            var textbox = this.textboxes[i];
            if (textbox.name == name) {
                return textbox;
            }
        }
    }
    clear(){
        this.textboxes = [];
    }
}class UIPayList {

    constructor() {
        this.arrowbutton = new UIArrowButton();
        this.paylists = [];
        this.listitem = new UIListItem();
    }
    add(options) {
        options.scrollposition = 0;
        options.max_paylist_items = 0;
        options.scrollbarsize = options.height - options.pagescrollbuttonheight - 2 * options.scrollbarwidth - options.border_width;
        options.scrollbar_y = options.scrollbarwidth + options.border_width;
        options.mousedown_scrollbar_y = null;
        options.setList = (params) => {
            options.list = params;
            this.update()
            return;
        }

        options.previousPage = () => {
            if (options.max_paylist_items < options.list.length) {
                if (options.scrollposition - options.max_paylist_items > 0) {
                    options.scrollposition -= options.max_paylist_items;
                    this.update();
                }
                else {
                    options.scrollposition = 0
                    this.update();
                }
            }
            return;
        }
        options.nextPage = () => {
            if (options.max_paylist_items < options.list.length) {
                var nextitem = options.scrollposition + 2 * options.max_paylist_items;
                if (nextitem <= options.list.length) {
                    options.scrollposition += options.max_paylist_items;
                    this.update();
                }
                else {
                    options.scrollposition = options.list.length - options.max_paylist_items;
                    this.update();
                }
            }
            return;
        }



        options.scrollup = (params) => {
            if (options.scrollposition > 0) {
                options.scrollposition -= 1;
                this.update();
            }
            return;
        }
        options.scrolldown = (params) => {
            var nextitem = options.scrollposition + options.max_paylist_items + 1;
            if (nextitem <= options.list.length) {
                options.scrollposition += 1;
                this.update();
            }
            return;
        }
        options.setSelected = (id) => {
            options.selectedID = id;
            this.update();
            return;
        }
        options.getSelectedItemIndex = () => {
            return options.selectedID;
        }
        options.setScrollPosition = (position) => {
            if (options.max_paylist_items < options.list.length) {

                if (position <= options.list.length - options.max_paylist_items && position > 0) {
                    options.scrollposition = position;
                    this.update();
                }
                else if (position > options.list.length - options.max_paylist_items) {
                    options.scrollposition = options.list.length - options.max_paylist_items;
                    this.update();
                }
                else if (position < 0) {
                    options.scrollposition = 0;
                    this.update();
                }
            }
        }


        //right scroll bar
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'up',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.scrollup
        });
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y + options.height - options.scrollbarwidth - options.pagescrollbuttonheight, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'down',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.scrolldown
        });
        //bottom Page Scroll Button
        this.arrowbutton.add({
            x: options.x, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'up',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.previousPage
        });
        this.arrowbutton.add({
            x: options.x + options.width / 2 + 2, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'down',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.nextPage
        });
        this.paylists.push(options);


        return options;
    }

    update() {
        this.listitem.clear()
        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            var x = paylist.x;
            var height = paylist.elementOptions.height;
            var font_size = paylist.elementOptions.font_size;
            var selectedBackground = paylist.elementOptions.selectedBackground;
            var foreground = paylist.foreground;
            var width = paylist.width - paylist.scrollbarwidth;
            paylist.max_paylist_items = Math.round((paylist.height - (paylist.pagescrollbuttonheight + 5)) / height - 0.49);
            var max_scrollbarheight = paylist.height - paylist.pagescrollbuttonheight - 2 * paylist.scrollbarwidth - paylist.border_width;
            paylist.scrollbarsize = this.getScrollbarSize(paylist.max_paylist_items, paylist.list.length) * max_scrollbarheight;
            paylist.scrollbar_y = (max_scrollbarheight - paylist.scrollbarsize)
                * (paylist.scrollposition / (paylist.list.length - paylist.max_paylist_items)) + paylist.scrollbarwidth + paylist.border_width / 2; // calculate scrollbar y position
            for (var j in paylist.list) {
                var index = j - paylist.scrollposition;
                if (index < paylist.max_paylist_items && index >= 0) {
                    var item = paylist.list[j];
                    var y = paylist.y + paylist.elementOptions.height * index;
                    this.listitem.add({
                        ...{
                            x: x, y: y, width: width, height: height, font_size: font_size, selected: paylist.selectedID, border_width: paylist.border_width,
                            selectedBackground: selectedBackground, foreground: foreground, callback: paylist.setSelected, id: j
                        }, ...item
                    });
                }
            }
        }
    }
    getScrollbarSize(max_paylist_items, list_lenght) {
        var scrollbarsize = (1 / (list_lenght / max_paylist_items));
        if (scrollbarsize > 1) {
            scrollbarsize = 1;
        }
        return scrollbarsize;
    }
    render(ctx) {

        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            ctx.font = paylist.font_size + 'px Courier';
            ctx.strokeStyle = paylist.border;

            var grd;
            if (paylist.grd_type == 'horizontal') {
                grd = ctx.createLinearGradient(paylist.x, paylist.y, paylist.x + paylist.width, paylist.y);
            }
            else if (paylist.grd_type == 'vertical') {
                grd = ctx.createLinearGradient(paylist.x, paylist.y, paylist.x, paylist.y + paylist.height - paylist.pagescrollbuttonheight);
            }
            if (paylist.grd_type) {
                var step_size = 1 / paylist.background.length;
                for (var j in paylist.background) {
                    grd.addColorStop(step_size * j, paylist.background[j]);
                    ctx.fillStyle = grd;
                }
            }
            if (paylist.background.length == 1) {
                ctx.fillStyle = paylist.background[0];
            }
            if (!paylist.border_radius) {
                ctx.fillRect(paylist.x, paylist.y, paylist.width, paylist.height - paylist.pagescrollbuttonheight);
                ctx.strokeRect(paylist.x, paylist.y, paylist.width, paylist.height - paylist.pagescrollbuttonheight);
            } else {
                roundRect(ctx, paylist.x, paylist.y, paylist.width, paylist.height - paylist.pagescrollbuttonheight, paylist.border_radius, paylist.border_width);
            }
            ctx.fillStyle = paylist.scrollbarbackground;
            ctx.fillRect(paylist.x + paylist.width - paylist.scrollbarwidth - paylist.border_width / 2, paylist.y + paylist.scrollbarwidth,
                paylist.scrollbarwidth + paylist.border_width / 2, paylist.height - paylist.pagescrollbuttonheight - paylist.scrollbarwidth);

            ctx.fillStyle = paylist.foreground;
            ctx.fillRect(paylist.x + paylist.width - paylist.scrollbarwidth - paylist.border_width / 2, paylist.y + paylist.scrollbar_y,
                paylist.scrollbarwidth + paylist.border_width / 2, paylist.scrollbarsize);

        }

        this.arrowbutton.render(ctx);
        this.listitem.render(ctx);
    }
    onClick(x, y) {
        this.arrowbutton.onClick(x, y);
        this.listitem.onClick(x, y);

        return;
    }
    onMouseDown(x, y) {
        this.arrowbutton.onMouseDown(x, y);
        this.listitem.onMouseDown(x, y);
        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            var startx = paylist.x + paylist.width - paylist.scrollbarwidth - paylist.border_width / 2;
            var starty = paylist.y + paylist.scrollbarwidth;
            var endx = paylist.x + paylist.width + paylist.scrollbarwidth + paylist.border_width / 2;
            var endy = paylist.y + paylist.height - paylist.pagescrollbuttonheight - paylist.scrollbarwidth;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                var top_scrollbar = paylist.y + paylist.scrollbar_y;
                var below_scrollbar = top_scrollbar + paylist.scrollbarsize;
                starty = paylist.y + paylist.scrollbar_y;
                endy = starty + paylist.scrollbarsize;
                if (x >= startx && x <= endx && y >= starty && y <= endy) {
                    //Mouse Down on Scrollbar
                    paylist.mousedown_scrollbar_y = y - starty;
                }
                else if (y < top_scrollbar) {
                    //Mouse Down Above scrollbar
                    paylist.previousPage();
                }
                else if (y > below_scrollbar) {
                    //Mouse Down below scrollbar
                    paylist.nextPage();
                }
                return;
            }

        }
        return;
    }
    onMouseUp(x, y) {
        this.arrowbutton.onMouseUp(x, y);
        this.listitem.onMouseUp(x, y);
        for (i in this.paylists) {
            var paylist = this.paylists[i];
            paylist.mousedown_scrollbar_y = null;
        }
        return;
    }
    onMouseMove(x, y) {
        this.arrowbutton.onMouseMove(x, y);
        this.listitem.onMouseMove(x, y);
        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            if (paylist.mousedown_scrollbar_y != null) {
                var scroll_y = (y - paylist.mousedown_scrollbar_y) - (paylist.y + paylist.scrollbarwidth)//calculating scroll bar distance
                var max_scrollbarheight = paylist.height - paylist.pagescrollbuttonheight - 2 * paylist.scrollbarwidth - paylist.border_width;
                var empty_scrollbar_space = max_scrollbarheight - paylist.scrollbarsize;
                var scroll_position = Math.round(((paylist.list.length - paylist.max_paylist_items) / empty_scrollbar_space) * scroll_y);
                paylist.setScrollPosition(scroll_position);
                //paylist.scrollbarsize
            }

        }

        return;
    }
    find(name) {
        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            if (paylist.name == name) {
                return paylist;
            }
        }
    }

}class UIListItem {
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
}class UIDragNDrop {
    constructor() {
        this.textbox = new UITextBox()
        this.dragndrops = [];
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
    }
    add(options) {
        this.dragndrops.push(options);
        this.textbox.add(options);
        return options;
    }
    render(ctx) {
        this.textbox.render(ctx);
    }
    onClick(x, y) {
        return;
    }
    onMouseDown(x, y) {
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            var startx = dragndrop.x;
            var starty = dragndrop.y;
            var endx = startx + dragndrop.width;
            var endy = starty + dragndrop.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                this.mouse_down = true;
                console.log(i);
                this.array_move(this.dragndrops, i, this.dragndrops.length - 1);
                this.textbox.textboxes = this.dragndrops;
                this.mouse_down_x = x - startx;
                this.mouse_down_y = y - starty;
                return;
            }
        }
        return;
    }
    onMouseUp(x, y) {
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
    }
    array_move(arr, old_index, new_index) {
        if (new_index >= arr.length) {
            var k = new_index - arr.length + 1;
            while (k--) {
                arr.push(undefined);
            }
        }
        arr.splice(new_index, 0, arr.splice(old_index, 1)[0]);
        return arr;
    };
    onMouseMove(x, y) {
        if (this.mouse_down) {
            var dragndrop = this.dragndrops[this.dragndrops.length - 1];
            
            var new_x = x - this.mouse_down_x;
            var new_y = y - this.mouse_down_y;
            dragndrop.x = new_x;
            dragndrop.y = new_y;
        }
        return;
    }
    find(name) {
        return;
    }
}