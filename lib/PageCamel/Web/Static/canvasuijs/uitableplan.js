class UITablePlan {
    constructor(canvas) {
        this.canvas = canvas;
        this.uitableplans = [];
        this.button = new UIButton(this.canvas);
        this.numpad = new UINumpad(this.canvas);
        this.textbox = new UITextBox(this.canvas);
        this.min_width_height = 24;
        this.bottom_bar_height = 150;
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
        options.inputDisabled = false;
        options.selected = null;
        options.is_room_selected = false;
        options.active_room = this.uitableplans.length;
        options.button = new UIButton(this.canvas);
        options.numpad = new UINumpad(this.canvas);
        options.textbox = new UITextBox(this.canvas);
        options.dragndrop = new UIDragNDrop(this.canvas);
        options.buttonrow = new UIButtonRow(this.canvas);
        options.colorpalet = new UIColorPalet(this.canvas);
        options.room_options = [];
        if (options.active === undefined) {
            options.active = true;
        }
        options.removeRoom = (room) => {
            options.undoable.splice(room, 1);
            options.redoable.splice(room, 1);
        }
        options.isSelected = (object_selected) => {
            if (options.selected != object_selected) {
                options.selected = object_selected;
                this.update();
            }
            if (options.selected != null) {
                var obj = options.textbox.find('tablename');
                obj.setText(options.selected.displaytext);
            }
        }
        options.disableInput = (state) => {
            options.inputDisabled = state;
        }
        options.setRoomActive = (room_number, color_select = true) => {

            var new_dragndrops = [];
            var rooms = options.buttonrow.find('rooms').getList();

            if (options.editable == true && rooms.length > 0 && color_select) {
                options.is_room_selected = true;
            }
            else {
                options.is_room_selected = false;
            }

            for (var i in options.dragndrop.dragndrops) {
                var group_id = options.dragndrop.dragndrops[i].group_id;
                for (var j in rooms) {
                    var room = rooms[j]
                    if (group_id == room.i) {
                        new_dragndrops.push(options.dragndrop.dragndrops[i]);
                    }
                }
            }
            options.dragndrop.dragndrops = new_dragndrops;
            options.active_room = room_number;
            options.dragndrop.setEditable(options.active_room, true);
            if (options.selected != undefined) {
                options.selected.selected = false; //Unselect all tables
                options.isSelected(null);
            }
            if (options.editable) {
                options.addToUndoable(0);
            }
            for (var i in options.dragndrop.dragndrops) {
                var dragndrop = options.dragndrop.dragndrops[i];
                if (options.active_room == dragndrop.group_id) {
                    dragndrop.active = true;
                }
                else {
                    dragndrop.active = false;
                }
            }
            this.update();
        }
        options.buttonrow.add({
            name: 'rooms',
            x: options.x + 10, y: options.y + options.height - this.bottom_bar_height + 10, width: options.width - 225, height: 80, gap: 10, callback: options.disableInput,
            dialog_data: { x: options.x, y: options.y, height: options.height, width: options.width },
            contain_height: options.height - this.bottom_bar_height,//contain position is for unselecting room when clicked inside this aria
            contain_width: options.width - 225,
            contain_x: options.x,
            contain_y: options.y,
            roomSelectCallback: options.setRoomActive,
            roomDeleteCallback: options.removeRoom,
            //callback: buttonSendMessage,
            //callbackData: { key: "ZAHLUNGSART_SELECTREST" },
            elementOptions: {
                hover_border: '#ffffff',
                grd_type: 'vertical',
                height: 70,
                width: 120,
                font_size: 25,
                border_radius: 10
            }
        });


        options.setTableActive = (number, state) => {
            for (var j in options.dragndrop.dragndrops) {
                var dragndrop = options.dragndrop.dragndrops[j];
                if (dragndrop.displaytext == number && number >= 0) {
                    dragndrop.table_active = state;
                    triggerRepaint();
                    options.setSQLData();
                    if (window.sendTablePlan) {
                        sendTablePlan();
                    }
                }
            }
        }

        options.duplicate = () => {
            if (options.selected != null) {
                options.dragndrop.add({ ...options.selected });
                options.selected.selected = false;
                options.selected = null;
                options.isSelected(options.dragndrop.dragndrops[options.dragndrop.dragndrops.length - 1]);
                options.selected.selected = true;
                options.selected.changed = true;
                if (options.selected.x + options.selected.width + 15 > options.selected.contain_x + options.selected.contain_width) {
                    options.selected.x = options.selected.contain_x;
                }
                if (options.selected.y + options.selected.height + 15 > options.selected.contain_y + options.selected.contain_height) {
                    options.selected.y = options.selected.contain_y;
                }
                options.selected.x += 15;
                options.selected.y += 15;

                options.dragndrop.changeHandler(options.selected);
            }
        }
        options.tableClicked = (table_number) => {
            if (options.editable == false && table_number != '' && options.callback !== undefined) {
                options.callback(table_number);
            }
        }
        options.tableEntered = (val) => {
            var obj = options.textbox.find(val);
            var obj_text = obj.getText();
            var table_number = parseFloat(obj_text.replace(',', '.'));
            if (table_number >= 0 && options.callback !== undefined) {
                options.callback(table_number);
            }
        }

        options.edit = () => {
            options.isSelected(null);
            options.undoable = [];
            options.redoable = [];
            options.buttonrow.find('rooms').edit();
            options.dragndrop.setEditable(options.active_room, true);
            options.editable = true;
            options.select = true;
            this.update();
            options.addToUndoable(0);
            options.setRoomActive(options.active_room, false);
        }
        options.colorInput = (color) => {
            if (options.selected != null) {
                if (options.selected.background != color[0]) {
                    console.log(color[0]);
                    options.selected.background = [color[0]];
                    options.selected.foreground = color[1];
                    options.selected.change(); //change gets called when something has to be added to undo
                }
            }
            else {
                options.buttonrow.find('rooms').changeColor(color);
            }
        }
        options.numberInput = (val) => {
            var obj = options.textbox.find('tablename');
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
            var obj = options.textbox.find(val.key);
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
        options.addToUndoable = (state) => {
            var sorted_rooms = options.buttonrow.find('rooms').getList();
            console.log(sorted_rooms.length, options.undoable.length)
            if (state == 0) {
                for (var i = 0; i < sorted_rooms.length - options.undoable.length; i++) {
                    options.undoable.push([[]]);
                    options.redoable.push([]);
                    for (var j in options.dragndrop.dragndrops) {
                        var dragndrop = options.dragndrop.dragndrops[j];
                        console.log('id', sorted_rooms[options.undoable.length - 1].i);
                        if (sorted_rooms[options.undoable.length - 1].i == dragndrop.group_id) {
                            console.log('Add undoable to', options.active_room, dragndrop);
                            options.undoable[options.undoable.length - 1][options.undoable[options.undoable.length - 1].length - 1].push({ ...dragndrop });
                        }
                    }

                }
            }
            if (options.undoable.length == 0) {
                options.undoable.push([[]]);
            }
            if (state != 0) {
                options.redoable[options.active_room] = [];
                console.log('try push:', options.undoable, options.active_room)
                options.undoable[options.active_room].push([])
                for (var j in options.dragndrop.dragndrops) {
                    var dragndrop = options.dragndrop.dragndrops[j];
                    if (options.active_room == dragndrop.group_id) {
                        console.log('Add undoable to', options.active_room, dragndrop);
                        options.undoable[options.active_room][options.undoable[options.active_room].length - 1].push({ ...dragndrop });
                    }
                }
            }
            console.log(options.undoable);
        }
        options.save = () => {
            options.buttonrow.find('rooms').stopEdit('save');
            options.dragndrop.setEditable(options.active_room, false);
            options.setSQLData();
            options.select = false;
            options.editable = false;
            options.circle = false;
            options.rect = false;
            options.redoable = [];
            options.undoable = [];
            this.update();
            if (window.sendTablePlan) {
                sendTablePlan();
            }
        }
        options.setList = (unixTime, data) => {
            var tableline = executeSQL("SELECT data, timestamp FROM tableplan WHERE id=?", options.name);

            var needtableupdate = 0;
            if (typeof tableline[0] === 'undefined' || typeof tableline[0].timestamp === 'undefined') {
                needtableupdate = 1;
            } else {
                var tabletimestamp = tableline[0].timestamp;
                if (tabletimestamp < unixTime) {
                    console.log("Unix time " + unixTime);
                    console.log("DB Time " + tabletimestamp);
                    needtableupdate = 1;
                }
            }
            console.log('needtableupdate: ' + needtableupdate);
            if (!needtableupdate) {
                return;
            }
            executeSQL("DELETE FROM tableplan WHERE id=?", options.name);
            executeSQL("INSERT INTO tableplan (id, data, timestamp)\
                VALUES (?, ?, ?);", options.name, JSON.stringify(data), unixTime);
            options.getSQLData();
        }
        options.getList = () => {
            var data = executeSQL("SELECT data, timestamp FROM tableplan WHERE id=?", options.name);
            if (typeof data[0] === 'undefined' || typeof data[0].timestamp === 'undefined') {
                return;
            }
            var timestamp = data[0].timestamp;
            var data = JSON.parse(data[0].data);
            return [timestamp, data]
        }
        options.setSQLData = () => {
            var unixTime = Math.floor(Date.now() / 1000);
            var sorted_rooms = options.buttonrow.find('rooms').getList();
            console.log('Created Rooms:', sorted_rooms);
            console.log('Created Tables:', options.dragndrop.dragndrops);
            if (sorted_rooms.length == 0 && options.dragndrop.dragndrops.length > 0) {
                options.buttonrow.find('rooms').setList([{ background: ['#0000FF'], displaytext: "", foreground: "#000000", i: 0 }]);
                sorted_rooms = options.buttonrow.find('rooms').getList();
                sorted_rooms = options.buttonrow.find('rooms').roomSelected(0);
            }
            var room_data = [];
            for (var i in sorted_rooms) {
                var room = sorted_rooms[i];
                room_data.push({ name: room.displaytext, background: room.background, foreground: room.foreground, tables: [] })
                for (var j in options.dragndrop.dragndrops) {
                    var dragndrop = options.dragndrop.dragndrops[j];
                    if (room.i == dragndrop.group_id) {
                        room_data[i].tables.push({ ...dragndrop });
                        var k = room_data[i].tables.length - 1;

                        room_data[i].tables[k].group_id = i;
                        room_data[i].tables[k].x = (room_data[i].tables[k].x - options.x) / (options.width - 225);
                        room_data[i].tables[k].y = (room_data[i].tables[k].y - options.y) / (options.height - this.bottom_bar_height);
                        room_data[i].tables[k].width = room_data[i].tables[k].width / (options.width - 225);
                        room_data[i].tables[k].height = room_data[i].tables[k].height / (options.height - this.bottom_bar_height);
                    }
                }
            }
            console.log('Saving Data:', room_data);
            executeSQL("DELETE FROM tableplan WHERE id=?", options.name);
            var data = JSON.stringify(room_data);
            executeSQL("INSERT INTO tableplan (id, data, timestamp)\
                VALUES (?, ?, ?);", options.name, data, unixTime);
        }
        options.getSQLData = () => {
            if (options.active) {
                var data = executeSQL("SELECT data, timestamp FROM tableplan WHERE id=?", options.name);
                if (typeof data[0] === 'undefined' || typeof data[0].timestamp === 'undefined') {
                    return;
                }
                var room_data = JSON.parse(data[0].data);
                var tables = [];
                console.log('LOADING ROOMDATA', room_data);
                options.room_options = []
                if (room_data.length > 0) {
                    for (var i in room_data) {
                        options.room_options.push({ displaytext: room_data[i].name, background: room_data[i].background, foreground: room_data[i].foreground });
                        var room = room_data[i].tables;
                        for (var j in room) {
                            var table = room[j]
                            tables.push({ ...table });
                            var k = tables.length - 1;
                            tables[k].selected = false;
                            tables[k].addToUndoable = options.addToUndoable;
                            tables[k].isSelected = options.isSelected;
                            tables[k].callback = options.tableClicked;
                            if (options.active_room == tables[k].group_id) {
                                tables[k].active = true;
                            }
                            else {
                                tables[k].active = false;
                            }
                            //convert relative positions
                            console.log(tables[k].x * (options.width - 225) + options.x)
                            tables[k].x = tables[k].x * (options.width - 225) + options.x;
                            tables[k].y = tables[k].y * (options.height - this.bottom_bar_height) + options.y;
                            tables[k].width = tables[k].width * (options.width - 225);
                            tables[k].height = tables[k].height * (options.height - this.bottom_bar_height);
                            tables[k].contain_height = options.height - this.bottom_bar_height;
                            tables[k].contain_width = options.width - 225;
                            tables[k].contain_x = options.x;
                            tables[k].contain_y = options.y;
                        }
                    }
                    console.log('room Data', room_data);
                    console.log('Tables:', tables);
                    console.log('Displaytexts:', options.room_options);
                    options.dragndrop.loadSaved(tables);
                    options.buttonrow.find('rooms').setList(options.room_options);
                    options.buttonrow.find('rooms').roomSelected(options.active_room);

                }
            }
        }

        options.cancel = () => {
            options.buttonrow.find('rooms').stopEdit();
            options.dragndrop.setEditable(options.active_room, false);
            options.editable = false;
            options.circle = false;
            options.selected = null;
            options.select = false;
            options.rect = false;
            options.undoable = [];
            options.redoable = [];
            options.dragndrop.dragndrops = [];
            options.getSQLData();
            this.update();
        }
        options.selectTable = () => {
            $(this.canvas).css('cursor', 'default');
            options.dragndrop.setEditable(options.active_room, true);
            options.circle = false;
            options.rect = false;
            options.select = true;
            this.update();
        }
        options.drawCircle = () => {
            $(this.canvas).css('cursor', 'crosshair');
            options.dragndrop.setEditable(options.active_room, false);
            options.circle = true;
            options.selected = null;
            options.select = false;
            options.rect = false;
            this.update();
        }
        options.drawRect = () => {
            options.dragndrop.setEditable(options.active_room, false);
            $(this.canvas).css('cursor', 'crosshair');
            options.rect = true;
            options.selected = null;
            options.select = false;
            options.circle = false;
            this.update();

        }
        options.undo = () => {
            if (options.undoable[options.active_room] != undefined) {
                console.log(options.active_room)
                if (options.undoable[options.active_room].length > 1) {
                    options.buttonrow.find('rooms').index = null;
                    options.is_room_selected = null;
                    options.dragndrop.replaceElementsByGropID(options.active_room, options.undoable[options.active_room][options.undoable[options.active_room].length - 2], true);
                    options.redoable[options.active_room].push(options.undoable[options.active_room][options.undoable[options.active_room].length - 1]);
                    options.undoable[options.active_room].pop();
                    if (options.selected != null) {
                        var obj = options.textbox.find('tablename');
                        obj.setText(options.selected.displaytext);
                    }
                    console.log(options.undoable);
                }
                this.update()
            }
        }
        options.redo = () => {
            if (options.redoable[options.active_room] != undefined) {
                if (options.redoable[options.active_room].length > 0) {
                    options.buttonrow.find('rooms').index = null;
                    options.is_room_selected = null;
                    options.dragndrop.replaceElementsByGropID(options.active_room, options.redoable[options.active_room][options.redoable[options.active_room].length - 1], true);
                    options.undoable[options.active_room].push(options.redoable[options.active_room][options.redoable[options.active_room].length - 1]);
                    options.redoable[options.active_room].pop();
                    if (options.circle || options.rect) {
                        options.dragndrop.setEditable(options.active_room, false);
                    }
                    else if (options.select) {
                        options.dragndrop.setEditable(options.active_room, true);
                    }
                    if (options.selected != null) {
                        var obj = options.textbox.find('tablename');
                        obj.setText(options.selected.displaytext);
                    }
                }
            }
        }
        options.deleteSelected = () => {
            options.selected = null;
            options.dragndrop.deleteSelected(options.active_room);
            options.buttonrow.find('rooms').deleteRoom(); //only trys to delete room if red square around it
            this.update();
        }
        options.getSQLData();

        this.uitableplans.push(options);
        this.update();
        return options;
    }
    update() {
        //this.dragndrop.clear();
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.button.clear();
            uitableplan.numpad.clear();
            uitableplan.colorpalet.clear();
            uitableplan.textbox.clear();
            if (uitableplan.active) {
                if (uitableplan.editable == false) {
                    uitableplan.button.add({
                        displaytext: '🖉 Bearbeiten',
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 20, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#009dff',
                        callback: uitableplan.edit,
                    });
                    uitableplan.numpad.add({
                        show_keys: { x: false, ZWS: false },
                        allow_keyboard: true,
                        background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000', grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 70, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
                        callback: uitableplan.numberInputTableSelect,
                        callbackData: { key: 'tableselect' }
                    });
                    uitableplan.button.add({
                        displaytext: 'Enter',
                        accept_keycode: [13],
                        background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 215, y: uitableplan.y + uitableplan.height - 80, width: 205, height: 70, border_radius: 10, font_size: 40, hover_border: '#32d600',
                        callback: uitableplan.tableEntered,
                        callbackData: 'tableselect'
                    });
                    uitableplan.textbox.add({
                        displaytext: '', name: 'tableselect',
                        background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 135, width: 190, height: 50, font_size: 30, align: 'right'
                    });
                }
                else {
                    uitableplan.button.add({
                        displaytext: '⮪',
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 10, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.undo,
                    });
                    uitableplan.button.add({
                        displaytext: '⮫',
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 70, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.redo,
                    });
                    uitableplan.button.add({
                        name: 'rect',
                        displaytext: '⬜',
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 130, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.drawRect,
                    });
                    uitableplan.button.add({
                        name: 'circle',
                        displaytext: '◯',
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 190, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.drawCircle,
                    });
                    uitableplan.button.add({
                        name: 'select',
                        displaytext: "🖰",
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 250, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.selectTable,
                    });
                    uitableplan.button.add({
                        displaytext: "⎘",
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 310, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.duplicate
                    });
                    uitableplan.button.add({
                        displaytext: "🗑️",
                        background: ['#ff0000', '#cc000a'], foreground: '#000000', border: '#ff0000', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 370, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#cc000a',
                        callback: uitableplan.deleteSelected,
                    });
                    uitableplan.button.add({
                        displaytext: '🗙 Abbrechen',
                        background: ['#ff948c', '#ff1100',], foreground: '#000000', border: '#ff948c', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 170, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#ff1100',
                        callback: uitableplan.cancel,
                    });
                    uitableplan.button.add({
                        displaytext: '💾 Speichern',
                        background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', hover_border: '#32d600', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 350, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18,
                        callback: uitableplan.save,
                    });
                    if (uitableplan.selected != null) {
                        uitableplan.numpad.add({
                            allow_keyboard: true,
                            show_keys: { x: false, ZWS: false },
                            background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000', grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
                            x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 50, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
                            callback: uitableplan.numberInput,
                            callbackData: { key: i }
                        });
                        uitableplan.textbox.add({
                            displaytext: uitableplan.selected.displaytext, name: 'tablename',
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 115, width: 190, height: 50, font_size: 30, align: 'right'
                        });
                    }
                    if (uitableplan.selected != null) {
                        //color Selector
                        uitableplan.colorpalet.add({
                            x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + 10, width: 205, height: 170, callback: uitableplan.colorInput,
                        });
                    }
                    else if (uitableplan.is_room_selected) {
                        uitableplan.colorpalet.add({
                            x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + 10, width: 205, height: uitableplan.height - 100, callback: uitableplan.colorInput,
                        });
                        uitableplan.button.add({
                            displaytext: "Umbenennen",
                            background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                            x: uitableplan.x + 430, y: uitableplan.y + uitableplan.height - 60, width: 120, height: 50, border_radius: 10, font_size: 20, hover_border: '#009dff',
                            callback: uitableplan.buttonrow.find('rooms').renameRoom, callbackData: uitableplan.active_room
                        });
                    }
                }
            }
            triggerRepaint();
        }
    }

    render(ctx) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.active == true) {
                ctx.fillStyle = uitableplan.background[0];
                ctx.lineWidth = uitableplan.border_width;
                ctx.fillRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
                ctx.fillStyle = '#A9A9A9';
                ctx.fillRect(uitableplan.x + uitableplan.border_width / 2, uitableplan.y + uitableplan.height - this.bottom_bar_height, uitableplan.width - uitableplan.border_width, this.bottom_bar_height - uitableplan.border_width / 2);
                ctx.fillRect(uitableplan.x + uitableplan.width - 225, uitableplan.y + uitableplan.border_width / 2, 225 - uitableplan.border_width / 2, uitableplan.height - uitableplan.border_width);
                ctx.strokeStyle = uitableplan.border;
                ctx.strokeRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
                if (uitableplan.draw.mousedown_x != null) {
                    if (uitableplan.rect) {
                        ctx.fillStyle = '#0000FF';
                        ctx.fillRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                            uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                    }
                    else if (uitableplan.circle) {
                        ctx.beginPath();
                        ctx.fillStyle = '#0000FF';
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

                if (uitableplan.select) {
                    var button = uitableplan.button.find('select');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('select');
                    if (button !== undefined) {
                        button.border = '#4fbcff';
                        button.hover_border = '#009dff';
                    }
                }
                if (uitableplan.circle) {
                    var button = uitableplan.button.find('circle');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('circle');
                    if (button !== undefined) {
                        button.border = '#4fbcff';
                        button.hover_border = '#009dff';
                    }
                }
                if (uitableplan.rect) {
                    var button = uitableplan.button.find('rect');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('rect');
                    if (button !== undefined) {
                        button.border = '#4fbcff';
                        button.hover_border = '#009dff';
                    }
                }
                uitableplan.button.render(ctx);
                uitableplan.numpad.render(ctx);

                uitableplan.textbox.render(ctx);
                uitableplan.dragndrop.render(ctx);
                uitableplan.colorpalet.render(ctx);
                uitableplan.buttonrow.render(ctx);
            }
        }

    }
    onClick(x, y) {

        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.buttonrow.onClick(x, y);
            if (!uitableplan.inputDisabled) {
                uitableplan.dragndrop.onClick(x, y);
                uitableplan.colorpalet.onClick(x, y);
                uitableplan.button.onClick(x, y);
                uitableplan.numpad.onClick(x, y);
            }
        }


    }

    onMouseDown(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.buttonrow.onMouseDown(x, y);
            if (!uitableplan.inputDisabled) {
                uitableplan.button.onMouseDown(x, y);
                uitableplan.colorpalet.onMouseDown(x, y);
                uitableplan.numpad.onMouseDown(x, y);
                if (!uitableplan.circle && !uitableplan.rect && uitableplan.editable) {
                    uitableplan.dragndrop.onMouseDown(x, y);
                }

                if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                    if (x > uitableplan.x && x < uitableplan.x + uitableplan.width - 225 && y > uitableplan.y && y < uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                        uitableplan.is_room_selected = false;
                        uitableplan.draw.mousedown_x = x - uitableplan.x;
                        uitableplan.draw.mousedown_y = y - uitableplan.y;
                        uitableplan.draw.mousemove_x = x - uitableplan.x;
                        uitableplan.draw.mousemove_y = y - uitableplan.y;
                        this.update();
                    }
                }
                else {
                    uitableplan.draw.mousedown_x = null;
                    uitableplan.draw.mousedown_y = null;

                }
                if (x > uitableplan.x && x < uitableplan.x + uitableplan.width - 225 && y > uitableplan.y && y < uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                    uitableplan.is_room_selected = false;
                    this.update();
                }
            }
        }


    }
    onMouseUp(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.active == true) {
                uitableplan.buttonrow.onMouseUp(x, y);
                if (!uitableplan.inputDisabled) {
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
                        if (y + height > uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                            y = uitableplan.y + uitableplan.height - this.bottom_bar_height - height;
                        }
                        if (uitableplan.rect) {
                            //console.log(uitableplan.active_room);
                            uitableplan.dragndrop.add({
                                displaytext: '', group_id: uitableplan.active_room, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - this.bottom_bar_height,
                                background: ['#0000FF'], foreground: '#ffffff', border: '#0579ff', border_width: 0, grd_type: 'vertical', editable: true, active: uitableplan.active,
                                x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked,
                            });
                            uitableplan.addToUndoable();
                        }
                        else if (uitableplan.circle) {
                            uitableplan.dragndrop.add({
                                displaytext: '', group_id: uitableplan.active_room, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - this.bottom_bar_height,
                                background: ['#0000FF'], foreground: '#ffffff', border: '#0579ff', border_width: 0, grd_type: 'vertical', editable: true, type: 'circle', active: uitableplan.active,
                                x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked,
                            });
                            uitableplan.addToUndoable();
                        }
                        uitableplan.draw.mousedown_x = null;
                        uitableplan.draw.mousedown_y = null;
                        uitableplan.draw.mousemove_x = null;
                        uitableplan.draw.mousemove_y = null;
                        this.update();
                    }
                    uitableplan.dragndrop.onMouseUp(x, y);
                    uitableplan.button.onMouseUp(x, y);
                    uitableplan.colorpalet.onMouseUp(x, y);
                    uitableplan.numpad.onMouseUp(x, y);
                }
            }
        }

    }
    onMouseMove(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.active) {
                uitableplan.buttonrow.onMouseMove(x, y);
                if (!uitableplan.inputDisabled) {
                    uitableplan.button.onMouseMove(x, y);
                    uitableplan.colorpalet.onMouseMove(x, y);
                    uitableplan.numpad.onMouseMove(x, y);
                    if (uitableplan.select) {
                        uitableplan.dragndrop.onMouseMove(x, y);
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
                        else if (y > uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                            uitableplan.draw.mousemove_y = uitableplan.height - this.bottom_bar_height;
                        }
                        triggerRepaint();
                    }
                    else {
                        uitableplan.draw.mousemove_x = null;
                        uitableplan.draw.mousemove_y = null;
                    }
                }
            }
        }



    }
    onKeyDown(e) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.buttonrow.onKeyDown(e);
            if (!uitableplan.inputDisabled) {
                uitableplan.button.onKeyDown(e);
                uitableplan.numpad.onKeyDown(e);
            }
        }
    }
    onKeyUp(e) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.buttonrow.onKeyUp(e);
        }
    }
    find(name) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.name == name) {
                return uitableplan;
            }
        }
    }
    clear() {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.dragndrop.clear();
            uitableplan.buttonrow.clear();
            uitableplan.button.clear();
            uitableplan.colorpalet.clear();
            uitableplan.numpad.clear();
            uitableplan.textbox.clear();
        }
    }
}
