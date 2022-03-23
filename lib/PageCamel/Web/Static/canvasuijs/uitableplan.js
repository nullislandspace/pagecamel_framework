class UITablePlan {
    constructor(canvas) {
        this.canvas = canvas;
        this.uitableplans = [];
        this.dragndrop = new UIDragNDrop(this.canvas);
        this.button = new UIButton(this.canvas);
        this.numpad = new UINumpad(this.canvas);
        this.textbox = new UITextBox(this.canvas);
        this.min_width_height = 24;
    }
    add(options) {
        options.editable = false;
        options.draw = { mousedown_x: null, mousedown_y: null, mousemove_x: null, mousemove_y: null };
        options.redoable = [];
        options.undoable = [];
        options.elements = [];
        options.select = false;
        options.circle = false;
        options.rect = false;
        options.selected = null;
        options.group_id = 0;
        options.tableClicked = (table_number) => {
            if (options.editable == false && table_number != '') {
                options.callback(table_number);
            }
        }
        options.tableEntered = (val) => {
            var obj = this.textbox.find(val);
            var obj_text = obj.getText();
            var table_number = parseFloat(obj_text.replace(',', '.'));
            if (table_number >= 0) {
                options.callback(table_number);
            }
        }
        options.isSelected = (object_selected) => {
            if (options.selected != object_selected) {
                options.selected = object_selected;
                this.update();
            }
            if (options.selected != null) {
                var obj = this.textbox.find(options.selected.group_id);
                obj.setText(options.selected.displaytext);
            }
        }
        options.edit = (group_id) => {
            options.isSelected(null);
            options.undoable = [];
            options.redoable = [];

            this.dragndrop.setEditable(group_id, true);
            options.editable = true;
            options.select = true;
            for (var i in this.dragndrop.dragndrops) {
                //add current state to undoable
                var dragndrop = this.dragndrop.dragndrops[i];
                if (dragndrop.group_id == group_id) {
                    dragndrop.changed = true;
                    this.dragndrop.changeHandler(dragndrop);
                    this.update();
                    return;
                }
            }
            options.undoable.push([]);

        }
        options.colorInput = (color) => {
            if (options.selected.background != color) {
                options.selected.background = color;
                options.selected.change(); //change gets called when something has to be added to undo
            }
        }
        options.numberInput = (val) => {
            var obj = this.textbox.find(val.key);
            var obj_text = options.selected.displaytext;
            if (val.value >= 0) {
                obj_text = obj_text + val.value
                obj.setText(obj_text);
                options.selected.displaytext = obj_text;
                options.selected.change();
            }
            else if (val.value == '⌫') {
                obj_text = obj_text.slice(0, -1)
                obj.setText(obj_text);
                options.selected.displaytext = obj_text;
                options.selected.change();
            }
        }
        options.numberInputTableSelect = (val) => {
            var obj = this.textbox.find(val.key);
            var obj_text = obj.getText();
            if (val.value >= 0 || val.value == ',') {
                obj_text = obj_text + val.value
                obj.setText(obj_text);
            }
            else if (val.value == '⌫') {
                obj_text = obj_text.slice(0, -1)
                obj.setText(obj_text);
            }
        }
        options.addToUndoable = (dragndrops) => {
            options.redoable = [];
            options.undoable.push([...dragndrops]);
        }
        options.save = (group_id) => {
            this.dragndrop.setEditable(group_id, false);
            options.setSQLData();
            options.select = false;
            options.editable = false;
            options.circle = false;
            options.rect = false;
            options.redoable = [];
            options.undoable = [];
            this.update();
        }
        options.setList = (data, unixTime) => {
            var tabletimestamp = executeSQL(`SELECT data, timestamp FROM tableplan WHERE id='${options.name}'`)[0].values[0];
            if (tabletimestamp < unixTime) {
                executeSQL(`DELETE FROM tableplan WHERE id='${options.name}';`);
                executeSQL(`INSERT INTO tableplan (id, data, timestamp)\
                    VALUES ('${options.name}','${JSON.stringify(data)}', '${unixTime}');`);
                getSQLData();
            }
        }
        options.getList = () => {
            var data = executeSQL(`SELECT data, timestamp FROM tableplan WHERE id='${options.name}'`);
            var timestamp = data[0].values[0][1];
            var data = JSON.parse(data[0].values[0][0]);
            return [timestamp, data]
        }
        options.setSQLData = () => {
            var unixTime = Math.floor(Date.now() / 1000);
            executeSQL(`DELETE FROM tableplan WHERE id='${options.name}';`);
            var data = options.undoable[options.undoable.length - 1]; //get current dragndrop data
            for (var i in data) {
                //calculate relative positions
                data[i].x = (data[i].x - options.x) / (options.width - 225);
                data[i].y = (data[i].y - options.y) / (options.height - 70);
                data[i].width = data[i].width / (options.width - 225);
                data[i].height = data[i].height / (options.height - 70);
            }
            data = JSON.stringify(data);
            executeSQL(`INSERT INTO tableplan (id, data, timestamp)\
            VALUES ('${options.name}','${data}', '${unixTime}');`);
        }
        options.getSQLData = () => {
            var data = executeSQL(`SELECT data, timestamp FROM tableplan WHERE id='${options.name}'`);
            var data = JSON.parse(data[0].values[0][0]);
            if (data.length > 0) {
                for (var i in data) {
                    data[i].selected = false;
                    data[i].addToUndoable = options.addToUndoable;
                    data[i].isSelected = options.isSelected;
                    data[i].callback = options.tableClicked;
                    //convert relative positions
                    data[i].x = data[i].x * (options.width - 225) + options.x;
                    data[i].y = data[i].y * (options.height - 70) + options.y;
                    data[i].width = data[i].width * (options.width - 225);
                    data[i].height = data[i].height * (options.height - 70);
                    data[i].contain_height = options.height - 70;
                    data[i].contain_width = options.width - 225;
                    data[i].contain_x = options.x;
                    data[i].contain_y = options.y;
                }
                this.dragndrop.loadSaved(options.group_id, data);
            }
        }
        options.cancel = (group_id) => {
            this.dragndrop.setEditable(group_id, false);
            options.editable = false;
            options.circle = false;
            options.selected = null;
            options.select = false;
            options.rect = false;
            options.undoable = [];
            options.redoable = [];
            this.dragndrop.dragndrops = [];
            options.getSQLData();
            this.update();
        }
        options.selectTable = (group_id) => {
            $(this.canvas).css('cursor', 'default');
            this.dragndrop.setEditable(group_id, true);
            options.circle = false;
            options.rect = false;
            options.select = true;
            this.update();
        }
        options.drawCircle = (group_id) => {
            $(this.canvas).css('cursor', 'crosshair');
            this.dragndrop.setEditable(group_id, false);
            options.circle = true;
            options.selected = null;
            options.select = false;
            options.rect = false;
            this.update();
        }
        options.drawRect = (group_id) => {
            this.dragndrop.setEditable(group_id, false);
            $(this.canvas).css('cursor', 'crosshair');
            options.rect = true;
            options.selected = null;
            options.select = false;
            options.circle = false;
            this.update();

        }
        options.undo = (group_id) => {
            if (options.undoable.length > 1) {
                this.dragndrop.replaceElementsByGropID(group_id, options.undoable[options.undoable.length - 2]);
                options.redoable.push(options.undoable[options.undoable.length - 1]);
                options.undoable.pop();
                if (options.selected != null) {
                    var obj = this.textbox.find(options.group_id);
                    obj.setText(options.selected.displaytext);
                }
            }
        }
        options.redo = (group_id) => {
            if (options.redoable.length > 0) {
                this.dragndrop.replaceElementsByGropID(group_id, options.redoable[options.redoable.length - 1]);
                options.undoable.push(options.redoable[options.redoable.length - 1]);
                options.redoable.pop();
                if (options.circle || options.rect) {
                    this.dragndrop.setEditable(group_id, false);
                }
                else if (options.select) {
                    this.dragndrop.setEditable(group_id, true);
                }
                if (options.selected != null) {
                    var obj = this.textbox.find(options.group_id);
                    obj.setText(options.selected.displaytext);
                }
            }
        }
        options.deleteSelected = (group_id) => {
            options.selected = null;
            this.dragndrop.deleteSelected(group_id);
            this.update();
        }
        this.uitableplans.push(options);
        this.update();
        return options;
    }
    update() {
        this.button.clear();
        this.numpad.clear();
        this.textbox.clear();
        //this.dragndrop.clear();
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.group_id = i;
            if (uitableplan.editable == false) {
                this.button.add({
                    displaytext: '🖉 Bearbeiten',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 20, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#009dff',
                    callback: uitableplan.edit,
                    callbackData: i
                });
                this.numpad.add({
                    show_keys: { x: false, ZWS: false },
                    background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000', grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
                    x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 70, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
                    callback: uitableplan.numberInputTableSelect,
                    callbackData: { key: i + 'tableselect' }
                });
                this.button.add({
                    displaytext: 'Enter',
                    background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 215, y: uitableplan.y + uitableplan.height - 80, width: 205, height: 70, border_radius: 10, font_size: 40, hover_border: '#32d600',
                    callback: uitableplan.tableEntered,
                    callbackData: i + 'tableselect'
                });
                this.textbox.add({
                    displaytext: '', name: i + 'tableselect',
                    background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                    x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 140, width: 190, height: 50, font_size: 30, align: 'right'
                });
            }
            else {
                this.button.add({
                    displaytext: '⮪',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 10, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                    callback: uitableplan.undo,
                    callbackData: i
                });
                this.button.add({
                    displaytext: '⮫',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 70, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                    callback: uitableplan.redo,
                    callbackData: i
                });
                this.button.add({
                    displaytext: '➕⬜',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 130, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                    callback: uitableplan.drawRect,
                    callbackData: i
                });
                this.button.add({
                    displaytext: '➕◯',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 190, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                    callback: uitableplan.drawCircle,
                    callbackData: i
                });
                this.button.add({
                    displaytext: "🖰",
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 250, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                    callback: uitableplan.selectTable,
                    callbackData: i
                });
                this.button.add({
                    displaytext: "🗑️",
                    background: ['#ff0000', '#cc000a'], foreground: '#000000', border: '#ff0000', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 310, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#cc000a',
                    callback: uitableplan.deleteSelected,
                    callbackData: i
                });
                this.button.add({
                    displaytext: '🗙 Abbrechen',
                    background: ['#ff948c', '#ff1100',], foreground: '#000000', border: '#ff948c', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 170, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#ff1100',
                    callback: uitableplan.cancel,
                    callbackData: i
                });
                this.button.add({
                    displaytext: '💾 Speichern',
                    background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 350, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#32d600',
                    callback: uitableplan.save,
                    callbackData: i
                });
                if (uitableplan.selected != null) {
                    this.numpad.add({
                        show_keys: { x: false, ZWS: false },
                        background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000', grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 70, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
                        callback: uitableplan.numberInput,
                        callbackData: { key: i }
                    });
                    this.textbox.add({
                        displaytext: '', name: i,
                        background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 140, width: 190, height: 50, font_size: 30, align: 'right'
                    });

                    //color Selector
                    this.button.add({
                        displaytext: "",
                        background: ['#493C2B'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + 10, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#493C2B']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#A46422'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 160, y: uitableplan.y + 10, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#A46422']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#EB8931'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 110, y: uitableplan.y + 10, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#EB8931']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#2F484E'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 60, y: uitableplan.y + 10, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#2F484E']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#44891A'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + 60, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#44891A']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#1B2632'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 160, y: uitableplan.y + 60, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#1B2632']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#005784'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 110, y: uitableplan.y + 60, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#005784']
                    });
                    this.button.add({
                        displaytext: "",
                        background: ['#31A2F2'], foreground: '#000000', border: '#ffffff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 60, y: uitableplan.y + 60, width: 40, height: 40, border_radius: 5, font_size: 30, hover_border: '#ffffff',
                        callback: uitableplan.colorInput,
                        callbackData: ['#31A2F2']
                    });

                }
            }
        }
        triggerRepaint();
    }

    render(ctx) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            ctx.fillStyle = uitableplan.background[0];
            ctx.lineWidth = uitableplan.border_width;
            ctx.fillRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            ctx.fillStyle = '#A9A9A9';
            ctx.fillRect(uitableplan.x + uitableplan.border_width / 2, uitableplan.y + uitableplan.height - 70, uitableplan.width - uitableplan.border_width, 70 - uitableplan.border_width / 2);
            ctx.fillRect(uitableplan.x + uitableplan.width - 225, uitableplan.y + uitableplan.border_width / 2, 225 - uitableplan.border_width / 2, uitableplan.height - uitableplan.border_width);
            ctx.strokeStyle = uitableplan.border;
            ctx.strokeRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            if (uitableplan.draw.mousedown_x != null) {
                if (uitableplan.rect) {
                    ctx.fillStyle = '#31A2F2';
                    ctx.fillRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                        uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                }
                else if (uitableplan.circle) {
                    ctx.beginPath();
                    ctx.fillStyle = '#31A2F2';
                    var ellipse_radius_x = (uitableplan.draw.mousedown_x - uitableplan.draw.mousemove_x) / 2;
                    var ellipse_radius_y = (uitableplan.draw.mousedown_y - uitableplan.draw.mousemove_y) / 2;
                    var ellipse_center_x = uitableplan.draw.mousedown_x + uitableplan.x - ellipse_radius_x;
                    var ellipse_center_y = uitableplan.draw.mousedown_y + uitableplan.y - ellipse_radius_y;
                    if (ellipse_radius_x < 0) {
                        ellipse_radius_x = (uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x) / 2
                        ellipse_center_x = uitableplan.draw.mousedown_x + uitableplan.x + ellipse_radius_x;
                    }
                    if (ellipse_radius_y < 0) {
                        ellipse_radius_y = (uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y) / 2
                        ellipse_center_y = uitableplan.draw.mousedown_y + uitableplan.y + ellipse_radius_y;
                    }
                    ctx.ellipse(ellipse_center_x, ellipse_center_y, ellipse_radius_x, ellipse_radius_y, 0, 0, 2 * Math.PI);
                    ctx.fill();

                }
            }
        }
        this.button.render(ctx);
        this.numpad.render(ctx);
        this.dragndrop.render(ctx);
        this.textbox.render(ctx);
    }
    onClick(x, y) {
        this.button.onClick(x, y);
        this.numpad.onClick(x, y);
        this.dragndrop.onClick(x, y);

    }

    onMouseDown(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (!uitableplan.circle && !uitableplan.rect && uitableplan.editable) {
                this.dragndrop.onMouseDown(x, y);
            }
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                if (x > uitableplan.x && x < uitableplan.x + uitableplan.width - 225 && y > uitableplan.y && y < uitableplan.y + uitableplan.height - 70) {
                    uitableplan.draw.mousedown_x = x - uitableplan.x;
                    uitableplan.draw.mousedown_y = y - uitableplan.y;
                    uitableplan.draw.mousemove_x = x - uitableplan.x;
                    uitableplan.draw.mousemove_y = y - uitableplan.y;
                }
            }
            else {
                uitableplan.draw.mousedown_x = null;
                uitableplan.draw.mousedown_y = null;

            }
        }
        this.button.onMouseDown(x, y);
        this.numpad.onMouseDown(x, y);

    }
    onMouseUp(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true) && uitableplan.draw.mousedown_x != null) {
                var x = 0;
                var y = 0;
                var width = 0;
                var height = 0;
                if (uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x > 0) {
                    x = uitableplan.draw.mousedown_x + uitableplan.x;
                    width = uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x;
                }
                else {
                    x = uitableplan.draw.mousemove_x + uitableplan.x;
                    width = uitableplan.draw.mousedown_x - uitableplan.draw.mousemove_x;
                }
                if (uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y > 0) {
                    y = uitableplan.draw.mousedown_y + uitableplan.y;
                    height = uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y;
                }
                else {
                    y = uitableplan.draw.mousemove_y + uitableplan.y;
                    height = uitableplan.draw.mousedown_y - uitableplan.draw.mousemove_y;
                }
                if (width < this.min_width_height) {
                    width = this.min_width_height;
                }
                if (height < this.min_width_height) {
                    height = this.min_width_height;
                }
                if (x + width > uitableplan.x + uitableplan.width - 225) {
                    x = uitableplan.x + uitableplan.width - 225 - width;
                }
                if (y + height > uitableplan.y + uitableplan.height - 70) {
                    y = uitableplan.y + uitableplan.height - 70 - height;
                }
                if (uitableplan.rect) {
                    this.dragndrop.add({
                        displaytext: '', group_id: i, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - 70,
                        background: ['#31A2F2'], foreground: '#000000', border: '#0579ff', border_width: 0, grd_type: 'vertical', editable: true,
                        x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked,
                    });
                }
                else if (uitableplan.circle) {
                    this.dragndrop.add({
                        displaytext: '', group_id: i, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - 70,
                        background: ['#31A2F2'], foreground: '#000000', border: '#0579ff', border_width: 0, grd_type: 'vertical', editable: true, type: 'circle',
                        x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked,
                    });
                }
                uitableplan.draw.mousedown_x = null;
                uitableplan.draw.mousedown_y = null;
                uitableplan.draw.mousemove_x = null;
                uitableplan.draw.mousemove_y = null;
                this.update();
            }
        }
        this.button.onMouseUp(x, y);
        this.numpad.onMouseUp(x, y);
        this.dragndrop.onMouseUp(x, y);
    }
    onMouseMove(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.select) {
                this.dragndrop.onMouseMove(x, y);
            }
            else if (uitableplan.rect || uitableplan.circle) {
                $(this.canvas).css('cursor', 'crosshair');
            }
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                uitableplan.draw.mousemove_x = x - uitableplan.x;
                uitableplan.draw.mousemove_y = y - uitableplan.y;
                if (x < uitableplan.x) {
                    uitableplan.draw.mousemove_x = 0;
                }
                else if (x > uitableplan.x + uitableplan.width - 225) {
                    uitableplan.draw.mousemove_x = uitableplan.width - 225;
                }
                if (y < uitableplan.y) {
                    uitableplan.draw.mousemove_y = 0;
                }
                else if (y > uitableplan.y + uitableplan.height - 70) {
                    uitableplan.draw.mousemove_y = uitableplan.height - 70;
                }
                triggerRepaint();
            }
            else {
                uitableplan.draw.mousemove_x = null;
                uitableplan.draw.mousemove_y = null;
            }
        }
        this.button.onMouseMove(x, y);
        this.numpad.onMouseMove(x, y);


    }
    find(name) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.name == name) {
                return uitableplan;
            }
        }
    }
}