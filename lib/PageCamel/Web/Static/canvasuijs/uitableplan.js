class UITablePlan {
    constructor(canvas) {
        this.canvas = canvas;
        this.uitableplans = [];
        this.min_width_height = 24;
        this.bottom_bar_height = 150;
        this.horizontal_lines_count = 40;
    }
    add(options) {
        options.active_tables = [];//[{table:displaytext, active_bills:[11.1, 11]}]
        options.editable = false;
        options.draw = { mousedown_x: null, mousedown_y: null, mousemove_x: null, mousemove_y: null };
        options.redoable = [];
        options.undoable = [];
        options.elements = [];
        options.select = false;
        options.circle = false;
        options.image = false;
        options.rect = false;
        options.text_label = false;
        options.text_label_displaytext = '';
        options.inputDisabled = false;
        options.selected = null;
        options.is_room_selected = false;
        options.active_room = this.uitableplans.length;
        options.grid_active = false;
        options.button = new UIButton(this.canvas);
        options.numpad = new UINumpad(this.canvas);
        options.textbox = new UITextBox(this.canvas);
        options.dragndrop = new UIDragNDrop(this.canvas);
        options.buttonrow = new UIButtonRow(this.canvas);
        options.colorpalet = new UIColorPalet(this.canvas);
        options.checkbox = new UICheckBox(this.canvas);
        options.textinput = new UITextInput(this.canvas);
        options.dialog = new UIDialog(this.canvas);
        options.background_imgs = []
        options.room_options = [];
        options.change_background_color = false;
        options.change_frame_color = false;
        options.distance = (options.height - this.bottom_bar_height) / this.horizontal_lines_count;
        if (options.active === undefined) {
            options.active = true;
        }
        options.removeRoom = (room) => {
            options.background_imgs.splice(room, 1);
            options.undoable.splice(room, 1);
            options.redoable.splice(room, 1);
            this.update();
        }
        options.setTableActive = (table, table_active) => {

            var active_table_length = 0
            for (var active_table of options.active_tables) {
                if (Math.floor(table) == active_table.table) {
                    if (table_active == false) {
                        if (active_table.active_bills.includes(table)) {
                            active_table.active_bills.splice(active_table.active_bills.indexOf(table), 1);
                        }
                    }
                    else if (!active_table.active_bills.includes(parseFloat(table))) {
                        active_table.active_bills.push(parseFloat(table));
                    }
                    for (var dragndrop of options.dragndrop.dragndrops) {
                        if (dragndrop.displaytext == Math.floor(table)) {
                            if (active_table.active_bills.length > 0 && (active_table.active_bills[0] > table || active_table.active_bills[0] < table || table_active == true || active_table.active_bills.length > 1)) {
                                dragndrop.setHighlight(true);
                            }
                            else {
                                dragndrop.setHighlight(false);
                            }
                        }
                    }
                    console.log('Set Table Active:', table, table_active, active_table);
                    return;
                }
            }
            var table_number = Math.floor(parseFloat(table));
            if (table_active == false) {
                options.active_tables.push({ table: table_number, active_bills: [] });
                active_table_length = 0;
            }
            else {
                options.active_tables.push({ table: table_number, active_bills: [parseFloat(table)] });
                active_table_length = 1;
            }
            for (var dragndrop of options.dragndrop.dragndrops) {
                if (dragndrop.displaytext == Math.floor(table)) {
                    if (active_table_length > 0 && (table > Math.floor(table) || table_active == true || active_table_length > 1)) {
                        dragndrop.setHighlight(true);
                    }
                    else {
                        dragndrop.setHighlight(false);
                    }
                }
            }
            console.log('Set Table Active:', table, table_active, active_table);
        }
        options.isSelected = (object_selected) => {
            if (options.selected != object_selected) {
                options.selected = object_selected;
                this.update();
            }
            if (options.selected != null) {
                var obj = options.textinput.find('tablename');
                obj.setText(options.selected.displaytext);
            }
        }
        options.enableDisableGrid = (state) => {
            options.grid_active = state;
            options.dragndrop.setGrid(state, options.distance);

        }
        options.disableButtonRowInput = (state) => {
            options.inputButtonRowDisabled = state;
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
            elementOptions: {
                hover_border: '#ffffff',
                grd_type: 'vertical',
                height: 70,
                width: 120,
                font_size: 25,
                border_radius: 10
            }
        });


        /*options.setTableActive = (number, state) => {
            for (var j in options.dragndrop.dragndrops) {
                var dragndrop = options.dragndrop.dragndrops[j];
                if (dragndrop.displaytext == number && number >= 0) {
                    dragndrop.table_active = state;
                    triggerRepaint();
                    options.setSQLData();
                    options.sendTablePlan();
                }
            }
        }*/

        options.duplicate = () => {
            if (options.selected != null) {
                options.dragndrop.add({ ...options.selected });
                options.selected.selected = false;
                options.selected = null;
                options.isSelected(options.dragndrop.dragndrops[options.dragndrop.dragndrops.length - 1]);
                options.selected.selected = true;
                options.selected.changed = true;
                var [x_corners, y_corners] = options.dragndrop.calculateCornerPositions(options.selected.x, options.selected.y, options.selected.width, options.selected.height, options.selected.angle);
                var center_x = (x_corners[0] + x_corners[1] + x_corners[2] + x_corners[3]) / 4
                var center_y = (y_corners[0] + y_corners[1] + y_corners[2] + y_corners[3]) / 4
                if (x_corners[3] + 15 > options.selected.contain_x + options.selected.contain_width) {
                    var offset = center_x - x_corners[0] - options.selected.width / 2;
                    options.selected.x = offset + options.selected.contain_x;
                }
                if (y_corners[3] + 15 > options.selected.contain_y + options.selected.contain_height) {
                    var offset = center_y - y_corners[0] - options.selected.height / 2;
                    options.selected.y = offset + options.selected.contain_y;
                }
                options.selected.x += 15;
                options.selected.y += 15;
                options.selected.center_x = options.selected.x + options.selected.width / 2;
                options.selected.center_y = options.selected.y + options.selected.height / 2;

                options.dragndrop.changeHandler(options.selected);
            }
        }
        options.handleTableInput = (table_number) => {
            if (options.editable == false && table_number != '' && options.callback !== undefined) {
                for (var active_table of options.active_tables) {
                    if (active_table.table == Math.floor(parseFloat(table_number)) && active_table.active_bills.length > 0) {
                        if ((active_table.active_bills.length == 1 && active_table.active_bills[0] != active_table.table) || active_table.active_bills.length > 1) {
                            options.disableButtonRowInput(true);
                            options.disableInput(true);
                            var table_select_list = [];
                            for (var table of active_table.active_bills) {
                                if (table != Math.floor(parseFloat(table_number))) {
                                    table_select_list.push({
                                        type: 'text',
                                        lineitem: [
                                            { location: 0.05, align: 'right', displaytext: String(table) },
                                        ]
                                    });
                                }
                            }
                            table_select_list.push({
                                type: 'text',
                                lineitem: [
                                    { location: 0.05, align: 'right', displaytext: String(Math.floor(parseFloat(table_number))) },
                                ]
                            });
                            options.dialog.add({
                                displaytext: 'Select Table:',
                                background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'selectTable',
                                hover_border: '#32d600', border_width: 3, width: 700, height: 400,
                                alpha_x: options.x, alpha_y: options.y, alpha_width: options.width, alpha_height: options.height,
                                type: 'select',
                                callback: (action) => {
                                    if (action == 'cancel') {
                                        options.disableButtonRowInput(false);
                                        options.disableInput(false);
                                        options.dialog.clear();
                                    }
                                    else if (options.dialog.find('selectTable').getSelectedItemIndex() != null) {
                                        options.disableButtonRowInput(false);
                                        options.disableInput(false);
                                        var selected_table = table_select_list[options.dialog.find('selectTable').getSelectedItemIndex()].lineitem[0].displaytext;
                                        options.callback(parseFloat(selected_table));
                                        options.dialog.clear();
                                    }
                                },
                            });
                            options.dialog.find('selectTable').setList(table_select_list);
                            return;
                        }
                    }
                }
                options.callback(table_number);
            }
        }
        options.tableClicked = (table_number) => {
            options.handleTableInput(table_number);
        }
        options.tableEntered = (val) => {
            var obj = options.textinput.find(val);
            var obj_text = obj.getText();
            var table_number = parseFloat(obj_text.replace(',', '.'));
            var table_exists = false;
            for (var dragndrop of options.dragndrop.dragndrops) {
                if (parseInt(dragndrop.displaytext) == Math.floor(table_number)) {
                    table_exists = true;
                }
            }
            if (table_number >= 0 && options.callback !== undefined && table_exists) {
                if (table_number == Math.round(table_number)) {
                    options.handleTableInput(table_number);
                }
                else {
                    options.callback(table_number);
                }
            }
        }

        options.edit = () => {
            for (var dragndrop of options.dragndrop.dragndrops) {
                if (dragndrop.highlight == true) {
                    options.disableInput(true);
                    options.disableButtonRowInput(true);
                    options.dialog.add({
                        background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'label',
                        hover_border: '#32d600', border_width: 3, width: 700, height: 400,
                        alpha_x: options.x, alpha_y: options.y, alpha_width: options.width, alpha_height: options.height,
                        type: 'alert', displaytext: _trquote('There are still unbilled tables open'),
                        callback: () => {

                            options.dialog.clear();
                            options.disableInput(false);
                            options.disableButtonRowInput(false);
                        }
                    });
                    return;
                }
            }
            for (var dragndrop of options.dragndrop.dragndrops) {
                dragndrop.edit_mode = true;
            }
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
        options.backgroundColorInput = (hex_color) => {
            hex_color = '#' + hex_color;
            if (isValidHexaCode(hex_color) && options.selected.background !== [hex_color]) {
                options.selected.background = [hex_color];
                options.addToUndoable();
            }
        }
        options.frameColorInput = (hex_color) => {
            hex_color = '#' + hex_color;
            if (isValidHexaCode(hex_color) && options.selected.background !== [hex_color]) {
                options.selected.border = hex_color;
                options.addToUndoable();
            }
        }
        options.colorInput = (color) => {
            if (options.selected != null) {
                if (options.change_background_color) {
                    if (options.selected.background != color[0]) {
                        options.textinput.find('table bg').setText(color[0].slice(1).toLowerCase());
                        options.selected.background = [color[0]];
                        options.selected.foreground = color[1];
                        options.selected.change(); //change gets called when something has to be added to undo
                    }
                }
                else {
                    if (options.selected.border != color[0]) {
                        options.textinput.find('table frame').setText(color[0].slice(1).toLowerCase());
                        options.selected.border = color[0];
                        options.selected.change(); //change gets called when something has to be added to undo
                    }
                }

            }
            else {
                options.buttonrow.find('rooms').changeColor(color);
            }
        }
        options.numberInput = (val) => {
            var new_text = options.textinput.find('tablename').getText();
            options.selected.displaytext = new_text;
            options.selected.change();
        }
        options.numberInputTableSelect = (val) => {
            var obj = options.textinput.find(val.key);
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
            if (state == 0) {
                for (var i = 0; i < sorted_rooms.length + 1 - options.undoable.length; i++) {
                    options.undoable.push([[]]);
                    options.redoable.push([]);
                    for (var j in options.dragndrop.dragndrops) {
                        var dragndrop = options.dragndrop.dragndrops[j];
                        try {
                            //temporary bug fix
                            if (sorted_rooms[options.undoable.length - 1].i == dragndrop.group_id) {
                                options.undoable[options.undoable.length - 1][options.undoable[options.undoable.length - 1].length - 1].push({ ...dragndrop });
                            }
                        }
                        catch {
                            if (sorted_rooms[options.undoable.length - 2].i == dragndrop.group_id) {
                                options.undoable[options.undoable.length - 1][options.undoable[options.undoable.length - 1].length - 1].push({ ...dragndrop });
                            }
                        }

                    }

                }
            }
            if (options.undoable.length == 0) {
                options.undoable.push([[]]);
            }
            if (state != 0) {
                options.redoable[options.active_room] = [];
                options.undoable[options.active_room].push([])
                for (var j in options.dragndrop.dragndrops) {
                    var dragndrop = options.dragndrop.dragndrops[j];
                    if (options.active_room == dragndrop.group_id) {
                        options.undoable[options.active_room][options.undoable[options.active_room].length - 1].push({ ...dragndrop });
                    }
                }
            }
        }
        options.save = () => {
            for (var dragndrop of options.dragndrop.dragndrops) {
                dragndrop.edit_mode = false;
            }
            options.buttonrow.find('rooms').stopEdit('save');
            options.dragndrop.setEditable(options.active_room, false);
            options.setSQLData();
            options.select = false;
            options.editable = false;
            options.circle = false;
            options.image = false;
            options.rect = false;
            options.redoable = [];
            options.undoable = [];
            this.update();
            options.sendTablePlan();
        }
        options.setList = (unixTime, data) => {
            if (options.editable == false) {
                var tableline = executeSQL("SELECT data, timestamp FROM tableplan WHERE id=?", options.name);
                console.log('Data of plan:', tableline);
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
            if ((sorted_rooms.length == 0) && options.dragndrop.dragndrops.length > 0) {
                options.buttonrow.find('rooms').setList([{ background: ['#0000FF'], displaytext: "", foreground: "#FFFFFF", i: 0 }]);
                sorted_rooms = options.buttonrow.find('rooms').getList();
                options.buttonrow.find('rooms').roomSelected(0);
            }
            var room_data = [];
            for (var i in sorted_rooms) {
                var room = sorted_rooms[i];
                if (options.background_imgs[i] !== undefined) {
                    room_data.push({
                        name: room.displaytext, background: room.background, foreground: room.foreground,
                        background_img: options.background_imgs[i].currentSrc, tables: []
                    });
                }
                else {
                    room_data.push({
                        name: room.displaytext, background: room.background, foreground: room.foreground,
                        background_img: undefined, tables: []
                    });
                }
                for (var j in options.dragndrop.dragndrops) {
                    var dragndrop = options.dragndrop.dragndrops[j];
                    if (room.i == dragndrop.group_id) {
                        room_data[i].tables.push({ ...dragndrop });
                        var k = room_data[i].tables.length - 1;
                        if (dragndrop.nextImage !== undefined) {
                            room_data[i].tables[k].nextImage = dragndrop.nextImage.currentSrc;
                        }
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
                        options.setBackground(room_data[i].background_img, i);
                        options.room_options.push({ displaytext: room_data[i].name, background: room_data[i].background, foreground: room_data[i].foreground });
                        var room = room_data[i].tables;
                        for (var j in room) {
                            var table = room[j]
                            tables.push({ ...table });
                            var k = tables.length - 1;
                            tables[k].selected = false;
                            tables[k].distance = options.distance;
                            options.grid_active = tables[k].grid_active;
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
                            tables[k].x = tables[k].x * (options.width - 225) + options.x;
                            tables[k].y = tables[k].y * (options.height - this.bottom_bar_height) + options.y;
                            tables[k].width = tables[k].width * (options.width - 225);
                            tables[k].height = tables[k].height * (options.height - this.bottom_bar_height);
                            tables[k].contain_height = options.height - this.bottom_bar_height;
                            tables[k].contain_width = options.width - 225;
                            tables[k].contain_x = options.x;
                            tables[k].edit_mode = options.editable;
                            tables[k].highlight = false;
                            tables[k].contain_y = options.y;
                            if (table.nextImage !== undefined) {
                                tables[k].nextImage = new Image();
                                tables[k].nextImage.src = table.nextImage;
                            }
                        }
                    }
                    console.log('room Data', room_data);
                    console.log('Tables:', tables);
                    console.log('Displaytexts:', options.room_options);
                    options.dragndrop.loadSaved(tables);
                    options.buttonrow.find('rooms').setList(options.room_options);
                    options.buttonrow.find('rooms').roomSelected(options.active_room);

                }
                else {
                    options.dragndrop.loadSaved([]);
                    options.buttonrow.find('rooms').setList([]);
                    options.buttonrow.find('rooms').roomSelected(0);
                }
            }
        }
        options.setBackground = (image, room = options.active_room) => {
            if (image !== undefined) {
                options.background_imgs[room] = new Image(options.width - 225, options.height - this.bottom_bar_height);
                options.background_imgs[room].src = image;
            }
            this.update();
            //var without_data_type = image.split("base64,")[1];
            //var plain_file = atob(without_data_type);
            //var fileType = plain_file.substring(0, 4);
            //console.log(fileType);

        }
        options.cancel = () => {
            for (var dragndrop of options.dragndrop.dragndrops) {
                dragndrop.edit_mode = false;
            }
            options.buttonrow.find('rooms').stopEdit();
            options.dragndrop.setEditable(options.active_room, false);
            options.editable = false;
            options.circle = false;
            options.image = false;
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
            for (var dragndrop of options.dragndrop.dragndrops) {
                dragndrop.edit_mode = true;
            }
            options.dragndrop.setEditable(options.active_room, true);
            options.circle = false;
            options.image = false;
            options.rect = false;
            options.text_label = false;
            options.select = true;
            this.update();
        }
        options.drawCircle = () => {
            for (var dragndrop of options.dragndrop.dragndrops) {
                dragndrop.edit_mode = false;
            }
            $(this.canvas).css('cursor', 'crosshair');
            options.dragndrop.setEditable(options.active_room, false);
            options.circle = true;
            options.image = false;
            options.selected = null;
            options.select = false;
            options.rect = false;
            options.text_label = false;
            this.update();
        }
        options.drawImage = (image) => {
            if (image !== undefined) {
                for (var dragndrop of options.dragndrop.dragndrops) {
                    dragndrop.edit_mode = false;
                }
                $(this.canvas).css('cursor', 'crosshair');
                options.nextImage = new Image();
                options.nextImage.src = image;
                options.dragndrop.setEditable(options.active_room, false);
                options.circle = false;
                options.image = true;
                options.selected = null;
                options.select = false;
                options.rect = false;
                options.text_label = false;
                this.update();
            }
        }
        options.drawRect = () => {
            for (var dragndrop of options.dragndrop.dragndrops) {
                dragndrop.edit_mode = false;
            }
            options.dragndrop.setEditable(options.active_room, false);
            $(this.canvas).css('cursor', 'crosshair');
            options.rect = true;
            options.image = false;
            options.selected = null;
            options.select = false;
            options.text_label = false;
            options.circle = false;
            this.update();
        }
        options.dialogClose = (action) => {
            options.disableInput(false);
            options.disableButtonRowInput(false);
            options.text_label_displaytext = '';
            if (action == 'ok') {
                for (var dragndrop of options.dragndrop.dragndrops) {
                    dragndrop.edit_mode = false;
                }
                options.text_label_displaytext = options.dialog.find('label').getText();
                options.dragndrop.setEditable(options.active_room, false);
                $(this.canvas).css('cursor', 'crosshair');
                options.rect = false;
                options.image = false;
                options.selected = null;
                options.select = false;
                options.circle = false;
                options.text_label = true;
            }
            options.dialog.clear();
            this.update();
        }
        options.undo = () => {
            if (options.undoable[options.active_room] != undefined) {
                if (options.undoable[options.active_room].length > 1) {
                    options.buttonrow.find('rooms').index = null;
                    options.is_room_selected = null;
                    for (var dragndrop of options.undoable[options.active_room][options.undoable[options.active_room].length - 2]) {
                        dragndrop.grid_active = options.grid_active;
                    }
                    options.dragndrop.replaceElementsByGropID(options.active_room, options.undoable[options.active_room][options.undoable[options.active_room].length - 2], true);
                    options.redoable[options.active_room].push(options.undoable[options.active_room][options.undoable[options.active_room].length - 1]);
                    options.undoable[options.active_room].pop();
                }
                this.update()
            }
        }
        options.redo = () => {
            if (options.redoable[options.active_room] != undefined) {
                if (options.redoable[options.active_room].length > 0) {
                    options.buttonrow.find('rooms').index = null;
                    options.is_room_selected = null;
                    for (var dragndrop of options.redoable[options.active_room][options.redoable[options.active_room].length - 1]) {
                        dragndrop.grid_active = options.grid_active;
                    }
                    options.dragndrop.replaceElementsByGropID(options.active_room, options.redoable[options.active_room][options.redoable[options.active_room].length - 1], true);
                    options.undoable[options.active_room].push(options.redoable[options.active_room][options.redoable[options.active_room].length - 1]);
                    options.redoable[options.active_room].pop();
                    if (options.circle || options.rect || options.image || options.text_label) {
                        options.dragndrop.setEditable(options.active_room, false);
                    }
                    else if (options.select) {
                        options.dragndrop.setEditable(options.active_room, true);
                    }
                    if (options.selected != null) {
                        var obj = options.textinput.find('tablename');
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
    getOffsetX(uitableplan) {
        var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
        var min_x_corner = x_corners[0];
        var center_x = (x_corners[0] + x_corners[1] + x_corners[2] + x_corners[3]) / 4
        var offset_x = center_x - min_x_corner - uitableplan.selected.width / 2;
        return offset_x
    }
    getOffsetY(uitableplan) {
        var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
        var min_y_corner = y_corners[0];
        var center_y = (y_corners[0] + y_corners[1] + y_corners[2] + y_corners[3]) / 4
        var offset_y = center_y - min_y_corner - uitableplan.selected.height / 2;
        return offset_y
    }
    update() {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            uitableplan.textinput.clear();
            uitableplan.button.clear();
            uitableplan.numpad.clear();
            uitableplan.checkbox.clear();
            uitableplan.colorpalet.clear();
            uitableplan.textbox.clear();
            if (uitableplan.active) {
                if (uitableplan.editable == false) {
                    uitableplan.button.add({
                        displaytext: _trquote('🖉 Edit'),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 20, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#009dff',
                        callback: uitableplan.edit,
                    });
                    uitableplan.numpad.add({
                        show_keys: { x: false, ZWS: false },
                        allow_keyboard: false,
                        background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000', grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 70, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
                        callback: uitableplan.numberInputTableSelect,
                        callbackData: { key: 'tableselect' }
                    });
                    uitableplan.button.add({
                        displaytext: _trquote('Enter'),
                        accept_keycode: [13],
                        background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 215, y: uitableplan.y + uitableplan.height - 80, width: 205, height: 70, border_radius: 10, font_size: 40, hover_border: '#32d600',
                        callback: uitableplan.tableEntered,
                        callbackData: 'tableselect'
                    });
                    uitableplan.textinput.add({
                        displaytext: '', name: 'tableselect', type: 'float',
                        background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                        x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 135, width: 190, height: 50, font_size: 30, align: 'left'
                    });
                }
                else {
                    uitableplan.button.add({
                        displaytext: _trquote('⮪'),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 10, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.undo,
                    });
                    uitableplan.button.add({
                        displaytext: _trquote('⮫'),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 70, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.redo,
                    });
                    uitableplan.button.add({
                        name: 'rect',
                        displaytext: _trquote('⬜'),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 130, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.drawRect,
                    });
                    uitableplan.button.add({
                        name: 'circle',
                        displaytext: _trquote('◯'),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 190, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.drawCircle,
                    });
                    uitableplan.button.add({
                        name: 'image',
                        displaytext: _trquote('🖼'),
                        select_file: true,
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 250, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.drawImage,
                    });
                    uitableplan.button.add({
                        name: 'text label',
                        displaytext: _trquote('TEXT'),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 310, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 20, hover_border: '#009dff',
                        callback: () => {
                            uitableplan.disableInput(true);
                            uitableplan.disableButtonRowInput(true);
                            uitableplan.dialog.add({
                                background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'label',
                                hover_border: '#32d600', border_width: 3, width: 700, height: 400, callback: uitableplan.dialogClose,
                                alpha_x: uitableplan.x, alpha_y: uitableplan.y, alpha_width: uitableplan.width, alpha_height: uitableplan.height,
                                type: 'textInput', displaytext: _trquote('Text Label:'), text: ''
                            });
                        },
                    });
                    uitableplan.button.add({
                        name: 'select',
                        displaytext: _trquote("🖰"),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 370, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.selectTable,
                    });
                    uitableplan.button.add({
                        displaytext: _trquote("⎘"),
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 430, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#009dff',
                        callback: uitableplan.duplicate
                    });
                    uitableplan.button.add({
                        displaytext: _trquote("🗑️"),
                        background: ['#ff0000', '#cc000a'], foreground: '#000000', border: '#ff0000', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + 490, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 10, font_size: 30, hover_border: '#cc000a',
                        callback: uitableplan.deleteSelected,
                    });
                    uitableplan.button.add({
                        displaytext: _trquote('🗙 Cancel'),
                        background: ['#ff948c', '#ff1100',], foreground: '#000000', border: '#ff948c', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 160, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 50, border_radius: 10, font_size: 20, hover_border: '#ff1100',
                        callback: uitableplan.cancel,
                    });
                    uitableplan.button.add({
                        displaytext: _trquote('💾 Save'),
                        background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', hover_border: '#32d600', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 320, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 50, border_radius: 10, font_size: 20,
                        callback: uitableplan.save,
                    });
                    uitableplan.button.add({
                        displaytext: _trquote('🖻 Background'),
                        select_file: true,
                        background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', hover_border: '#009dff', border_width: 3, grd_type: 'vertical',
                        x: uitableplan.x + uitableplan.width - 480, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 50, border_radius: 10, font_size: 20,
                        callback: uitableplan.setBackground,
                    });
                    uitableplan.checkbox.add({
                        displaytext: _trquote('Grid on/off'), align: 'right', checked: uitableplan.grid_active,
                        background: ['#ffffff'], foreground: '#000000', border: '#000000', hover_border: '#009dff', border_width: 2, font_size: 17,
                        x: uitableplan.x + uitableplan.width - 225 + 10, y: uitableplan.y + 10, width: 25, height: 25, border_radius: 2,
                        callback: uitableplan.enableDisableGrid,
                    });
                    if (uitableplan.selected != null) {
                        if (uitableplan.selected.type != 'text') {
                            uitableplan.textinput.add({
                                displaytext: uitableplan.selected.displaytext, name: 'tablename', label: _trquote('Table Nr.'),
                                background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                                x: uitableplan.x + uitableplan.width - 100, y: uitableplan.y + 40, width: 90, height: 50, font_size: 30, align: 'left',
                                callback: uitableplan.numberInput, type: 'number'
                            });
                        }
                        else {
                            uitableplan.textinput.add({
                                displaytext: uitableplan.selected.displaytext, name: 'tablename', label: _trquote('Text:'),
                                background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                                x: uitableplan.x + uitableplan.width - 150, y: uitableplan.y + 40, width: 140, height: 40, font_size: 25, align: 'left',
                                callback: uitableplan.numberInput, type: 'text'
                            });
                        }
                        var offset_x = this.getOffsetX(uitableplan);
                        uitableplan.textinput.add({
                            displaytext: String(Math.round(uitableplan.selected.x - uitableplan.x - offset_x)), name: 'posx', type: 'number', label: _trquote('X:'),
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 225 - 200, y: uitableplan.y + uitableplan.height - this.bottom_bar_height + 5,
                            width: 80, height: 35, font_size: 25, align: 'left',
                            callback: (posx) => {
                                var offset_x = this.getOffsetX(uitableplan);
                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(parseInt(posx) + uitableplan.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var max_x_corner = x_corners[3] + offset_x;
                                if (posx !== '' && max_x_corner <= uitableplan.x + uitableplan.width - 225) {
                                    if (uitableplan.selected.x != parseInt(posx) + uitableplan.x + offset_x) {
                                        uitableplan.selected.x = parseInt(posx) + uitableplan.x + offset_x;
                                        uitableplan.addToUndoable();
                                    }
                                    else {
                                        uitableplan.selected.x = parseInt(posx) + uitableplan.x + offset_x;
                                    }
                                }
                                else if (posx === '') {
                                    if (uitableplan.selected.x != uitableplan.x + offset_x) {
                                        uitableplan.selected.x = uitableplan.x + offset_x;
                                        uitableplan.addToUndoable();
                                    }
                                    else {
                                        uitableplan.selected.x = uitableplan.x + offset_x;
                                    }

                                }
                                else if (max_x_corner > uitableplan.x + uitableplan.width - 225) {
                                    if (uitableplan.selected.x != uitableplan.x + uitableplan.width - 225 - uitableplan.selected.width - offset_x) {
                                        uitableplan.selected.x = uitableplan.x + uitableplan.width - 225 - uitableplan.selected.width - offset_x;
                                        uitableplan.addToUndoable();
                                    }
                                    else {
                                        uitableplan.selected.x = uitableplan.x + uitableplan.width - 225 - uitableplan.selected.width - offset_x;
                                    }
                                }
                                else {
                                    return
                                }
                                uitableplan.selected.center_x = uitableplan.selected.x + uitableplan.selected.width / 2;
                                uitableplan.selected.center_y = uitableplan.selected.y + uitableplan.selected.height / 2;
                            }
                        });
                        var offset_y = this.getOffsetY(uitableplan);
                        uitableplan.textinput.add({
                            displaytext: String(Math.round(uitableplan.selected.y - uitableplan.y - offset_y)), name: 'posy', type: 'number', label: _trquote('Y:'),
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 225 - 200, y: uitableplan.y + uitableplan.height - this.bottom_bar_height + 45,
                            width: 80, height: 35, font_size: 25, align: 'left',
                            callback: (posy) => {
                                var offset_y = this.getOffsetY(uitableplan);
                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, parseInt(posy) + uitableplan.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var max_y_corner = y_corners[3] + offset_y;
                                if (posy !== '' && max_y_corner <= uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                                    if (uitableplan.selected.y != parseInt(posy) + uitableplan.y + offset_y) {
                                        uitableplan.selected.y = parseInt(posy) + uitableplan.y + offset_y;
                                        uitableplan.addToUndoable();
                                    }
                                    else {
                                        uitableplan.selected.y = parseInt(posy) + uitableplan.y + offset_y;
                                    }
                                }
                                else if (posy === '') {
                                    if (uitableplan.selected.y != uitableplan.y + offset_y) {
                                        uitableplan.selected.y = uitableplan.y + offset_y;
                                        uitableplan.addToUndoable();
                                    }
                                    else {
                                        uitableplan.selected.y = uitableplan.y + offset_y;
                                    }
                                }
                                else if (max_y_corner > uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                                    if (uitableplan.selected.y != uitableplan.y + uitableplan.height - this.bottom_bar_height - uitableplan.selected.height - offset_y) {
                                        uitableplan.selected.y = uitableplan.y + uitableplan.height - this.bottom_bar_height - uitableplan.selected.height - offset_y;
                                        uitableplan.addToUndoable();
                                    }
                                    else {
                                        uitableplan.selected.y = uitableplan.y + uitableplan.height - this.bottom_bar_height - uitableplan.selected.height - offset_y;
                                    }
                                }
                                else {
                                    return
                                }
                                uitableplan.selected.center_x = uitableplan.selected.x + uitableplan.selected.width / 2;
                                uitableplan.selected.center_y = uitableplan.selected.y + uitableplan.selected.height / 2;

                            }
                        });
                        uitableplan.textinput.add({
                            displaytext: String(Math.round(uitableplan.selected.height)), name: 'height', type: 'number', label: _trquote('Height:'),
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 225 - 40, y: uitableplan.y + uitableplan.height - this.bottom_bar_height + 45,
                            width: 80, height: 35, font_size: 25, align: 'left', callback: (height) => {
                                var max_height;
                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var center_x = (x_corners[0] + x_corners[1] + x_corners[2] + x_corners[3]) / 4;
                                var center_y = (y_corners[0] + y_corners[1] + y_corners[2] + y_corners[3]) / 4;
                                var max_x_corner = x_corners[3];
                                var min_x_corner = x_corners[0] + 0.1;
                                var max_y_corner = y_corners[3];
                                var min_y_corner = y_corners[0];
                                var top_corner = rotate(center_x, center_y, uitableplan.selected.x, uitableplan.selected.y, Math.abs(uitableplan.selected.angle) - 360);
                                var bottom_corner = rotate(center_x, center_y, uitableplan.selected.x, uitableplan.selected.y + uitableplan.selected.height, Math.abs(uitableplan.selected.angle) - 360);
                                var vertical;
                                var horizontal;
                                var wall_distance_right = uitableplan.x + uitableplan.width - 225 - max_x_corner;
                                var wall_distance_left = min_x_corner - uitableplan.x;
                                var wall_distance_up = min_y_corner - uitableplan.y
                                var wall_distance_down = uitableplan.y + uitableplan.height - this.bottom_bar_height - max_y_corner;
                                var angle = Math.abs(uitableplan.selected.angle);

                                if (angle > 0 && angle < 180) {
                                    vertical = bottom_corner[1] - top_corner[1];
                                    horizontal = bottom_corner[0] - top_corner[0];
                                    max_height = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_right)) ** 2 + (horizontal + wall_distance_right) ** 2);
                                }
                                else {
                                    vertical = top_corner[1] - bottom_corner[1];
                                    horizontal = top_corner[0] - bottom_corner[0];
                                    max_height = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_left)) ** 2 + (horizontal + wall_distance_left) ** 2);
                                }

                                if (angle > 90 && angle < 270) {
                                    horizontal = top_corner[1] - bottom_corner[1];
                                    vertical = top_corner[0] - bottom_corner[0];
                                    var new_max_height = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_up)) ** 2 + (horizontal + wall_distance_up) ** 2);
                                    if (new_max_height < max_height) {
                                        max_height = new_max_height
                                    }
                                }

                                else {
                                    horizontal = bottom_corner[1] - top_corner[1];
                                    vertical = bottom_corner[0] - top_corner[0];
                                    var new_max_height = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_down)) ** 2 + (horizontal + wall_distance_down) ** 2);
                                    if (new_max_height < max_height) {
                                        max_height = new_max_height
                                    }
                                }

                                if (parseInt(height) < max_height && parseInt(height) > uitableplan.dragndrop.box_size + 2) {
                                    if (parseInt(height) != uitableplan.selected.height) {
                                        uitableplan.addToUndoable();
                                    }

                                    uitableplan.selected.height = parseInt(height);
                                }
                                else if (parseInt(height) < uitableplan.dragndrop.box_size + 2) {
                                    if (uitableplan.dragndrop.box_size + 2 != uitableplan.selected.height) {
                                        uitableplan.addToUndoable();
                                    }
                                    uitableplan.selected.height = uitableplan.dragndrop.box_size + 2;
                                }
                                else if (parseInt(height) > max_height) {
                                    if (max_height != uitableplan.selected.height) {
                                        uitableplan.addToUndoable();
                                    }
                                    uitableplan.selected.height = max_height;
                                }
                                //Neu berechnung von center nach größen änderung
                                [uitableplan.selected.center_x, uitableplan.selected.center_y] = rotate(uitableplan.selected.center_x, uitableplan.selected.center_y, uitableplan.selected.x + uitableplan.selected.width / 2, uitableplan.selected.y + uitableplan.selected.height / 2, -uitableplan.selected.angle);
                                uitableplan.selected.x = uitableplan.selected.center_x - uitableplan.selected.width / 2;
                                uitableplan.selected.y = uitableplan.selected.center_y - uitableplan.selected.height / 2;

                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var min_x_corner = x_corners[0];
                                uitableplan.textinput.find('posx').setText(String(Math.round(min_x_corner - uitableplan.x)));
                                var min_y_corner = y_corners[0];
                                uitableplan.textinput.find('posy').setText(String(Math.round(min_y_corner - uitableplan.y)));

                            }
                        });
                        uitableplan.textinput.add({
                            displaytext: String(Math.round(uitableplan.selected.width)), name: 'width', type: 'number', label: _trquote('Width:'),
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 225 - 40, y: uitableplan.y + uitableplan.height - this.bottom_bar_height + 5,
                            width: 80, height: 35, font_size: 25, align: 'left', callback: (width) => {
                                var max_width;
                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var center_x = (x_corners[0] + x_corners[1] + x_corners[2] + x_corners[3]) / 4;
                                var center_y = (y_corners[0] + y_corners[1] + y_corners[2] + y_corners[3]) / 4;
                                var max_x_corner = x_corners[3];
                                var min_x_corner = x_corners[0];
                                var max_y_corner = y_corners[3];
                                var min_y_corner = y_corners[0];
                                var top_corner = rotate(center_x, center_y, uitableplan.selected.x, uitableplan.selected.y, Math.abs(uitableplan.selected.angle) - 360);
                                var bottom_corner = rotate(center_x, center_y, uitableplan.selected.x + uitableplan.selected.width, uitableplan.selected.y, Math.abs(uitableplan.selected.angle) - 360);
                                var vertical;
                                var horizontal;
                                var wall_distance_right = uitableplan.x + uitableplan.width - 225 - max_x_corner;
                                var wall_distance_left = min_x_corner - uitableplan.x;
                                var wall_distance_up = min_y_corner - uitableplan.y
                                var wall_distance_down = uitableplan.y + uitableplan.height - this.bottom_bar_height - max_y_corner;
                                var angle = Math.abs(uitableplan.selected.angle);

                                if (angle > 90 && angle < 270) {
                                    vertical = top_corner[1] - bottom_corner[1];
                                    horizontal = top_corner[0] - bottom_corner[0];
                                    max_width = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_left)) ** 2 + (horizontal + wall_distance_left) ** 2);
                                }
                                else {
                                    vertical = bottom_corner[1] - top_corner[1];
                                    horizontal = bottom_corner[0] - top_corner[0];
                                    max_width = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_right)) ** 2 + (horizontal + wall_distance_right) ** 2);
                                }

                                if (angle > 0 && angle < 180) {
                                    horizontal = top_corner[1] - bottom_corner[1];
                                    vertical = top_corner[0] - bottom_corner[0];
                                    var new_max_width = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_up)) ** 2 + (horizontal + wall_distance_up) ** 2);
                                    if (new_max_width < max_width) {
                                        max_width = new_max_width
                                    }
                                }

                                else {
                                    horizontal = bottom_corner[1] - top_corner[1];
                                    vertical = bottom_corner[0] - top_corner[0];
                                    var new_max_width = Math.sqrt((vertical / horizontal * (horizontal + wall_distance_down)) ** 2 + (horizontal + wall_distance_down) ** 2);
                                    if (new_max_width < max_width) {
                                        max_width = new_max_width
                                    }
                                }

                                if (parseInt(width) < max_width && parseInt(width) > uitableplan.dragndrop.box_size + 2) {
                                    if (parseInt(width) != uitableplan.selected.width) {
                                        uitableplan.addToUndoable();
                                    }

                                    uitableplan.selected.width = parseInt(width);
                                }
                                else if (parseInt(width) < uitableplan.dragndrop.box_size + 2) {
                                    if (uitableplan.dragndrop.box_size + 2 != uitableplan.selected.width) {
                                        uitableplan.addToUndoable();
                                    }
                                    uitableplan.selected.width = uitableplan.dragndrop.box_size + 2;
                                }
                                else if (parseInt(width) > max_width) {
                                    if (max_width != uitableplan.selected.width) {
                                        uitableplan.addToUndoable();
                                    }
                                    uitableplan.selected.width = max_width;
                                }
                                //Neu berechnung von center nach größen änderung
                                [uitableplan.selected.center_x, uitableplan.selected.center_y] = rotate(uitableplan.selected.center_x, uitableplan.selected.center_y, uitableplan.selected.x + uitableplan.selected.width / 2, uitableplan.selected.y + uitableplan.selected.height / 2, -uitableplan.selected.angle);
                                uitableplan.selected.x = uitableplan.selected.center_x - uitableplan.selected.width / 2;
                                uitableplan.selected.y = uitableplan.selected.center_y - uitableplan.selected.height / 2;

                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var min_x_corner = x_corners[0];
                                uitableplan.textinput.find('posx').setText(String(Math.round(min_x_corner - uitableplan.x)));
                                var min_y_corner = y_corners[0];
                                uitableplan.textinput.find('posy').setText(String(Math.round(min_y_corner - uitableplan.y)));
                            }
                        });
                        uitableplan.textinput.add({
                            displaytext: String(Math.abs(Math.round(uitableplan.selected.angle))), name: 'angle', type: 'number', label: _trquote('Angle:'),
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 225 + 130, y: uitableplan.y + uitableplan.height - this.bottom_bar_height + 45,
                            width: 80, height: 35, font_size: 25, align: 'left', callback: (angle) => {
                                var new_angle = parseInt(angle);
                                if (angle.length > 3) {
                                    new_angle = parseInt(angle.substring(0, 3));
                                    uitableplan.textinput.find('angle').setText(angle.substring(0, 3));
                                    uitableplan.textinput.find('angle').cursorPos = 3;
                                }
                                else if (angle > 360) {
                                    uitableplan.textinput.find('angle').setText(angle.substring(0, 2));
                                    uitableplan.textinput.find('angle').cursorPos = 2;
                                    new_angle = parseInt(angle.substring(0, 2));
                                }
                                else if (angle == '') {
                                    new_angle = 0;
                                }
                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, new_angle);
                                if (x_corners[0] < uitableplan.x || x_corners[3] > uitableplan.x + uitableplan.width - 225 || y_corners[0] < uitableplan.y || y_corners[3] > uitableplan.y + uitableplan.height - this.bottom_bar_height) {
                                    //check if illegal angle
                                    new_angle = uitableplan.selected.angle;
                                }
                                if (uitableplan.selected.angle != new_angle) {
                                    uitableplan.selected.angle = -new_angle;
                                    uitableplan.addToUndoable();
                                }
                                var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                                var min_x_corner = x_corners[0];
                                uitableplan.textinput.find('posx').setText(String(Math.round(min_x_corner - uitableplan.x)));
                                var min_y_corner = y_corners[0];
                                uitableplan.textinput.find('posy').setText(String(Math.round(min_y_corner - uitableplan.y)));
                            }
                        });
                    }
                    if (uitableplan.selected != null) {
                        //color Selector
                        if (uitableplan.selected.type != 'image') {
                            uitableplan.button.add({
                                displaytext: _trquote('Background  Color'), name: 'background color',
                                background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                                x: uitableplan.x + uitableplan.width - 225 + 10, y: uitableplan.y + 100, width: 205, height: 50, border_radius: 10, font_size: 20, hover_border: '#009dff',
                                callback: () => {
                                    uitableplan.change_background_color = true;
                                    uitableplan.change_frame_color = false;
                                    this.update();
                                }
                            });
                            uitableplan.textinput.add({
                                displaytext: uitableplan.selected.background[0].slice(1).toLowerCase(), name: 'table bg', label: _trquote('Background: #'),
                                background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                                x: uitableplan.x + uitableplan.width - 225 + 135, y: uitableplan.y + uitableplan.height - this.bottom_bar_height - 40, width: 80, height: 35, font_size: 21, align: 'left',
                                callback: uitableplan.backgroundColorInput, type: 'text'
                            });
                        }
                        else {
                            uitableplan.change_background_color = false;
                        }
                        uitableplan.button.add({
                            displaytext: _trquote('Frame Color'), name: 'frame color',
                            background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                            x: uitableplan.x + uitableplan.width - 225 + 10, y: uitableplan.y + 160, width: 205, height: 50, border_radius: 10, font_size: 20, hover_border: '#009dff',
                            callback: () => {
                                uitableplan.change_background_color = false;
                                uitableplan.change_frame_color = true;
                                this.update();
                            }
                        });
                        uitableplan.textinput.add({
                            displaytext: uitableplan.selected.border.slice(1).toLowerCase(), name: 'table frame', label: _trquote('Frame: #'),
                            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                            x: uitableplan.x + uitableplan.width - 225 + 135, y: uitableplan.y + uitableplan.height - this.bottom_bar_height - 80, width: 80, height: 35, font_size: 21, align: 'left',
                            callback: uitableplan.frameColorInput, type: 'text'
                        });
                        if (uitableplan.change_background_color || uitableplan.change_frame_color) {
                            uitableplan.colorpalet.add({
                                x: uitableplan.x + uitableplan.width - 225 + 10, y: uitableplan.y + 220, width: 205, height: uitableplan.height - this.bottom_bar_height - 300, callback: uitableplan.colorInput,
                            });
                        }
                    }
                    else if (uitableplan.is_room_selected) {
                        uitableplan.colorpalet.add({
                            x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + 40, width: 205, height: uitableplan.height - 170, callback: uitableplan.colorInput,
                        });
                        uitableplan.button.add({
                            displaytext: _trquote('Rename'),
                            background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                            x: uitableplan.x + 550, y: uitableplan.y + uitableplan.height - 60, width: 120, height: 50, border_radius: 10, font_size: 20, hover_border: '#009dff',
                            callback: uitableplan.buttonrow.find('rooms').renameRoom
                        });
                    }
                    if (uitableplan.background_imgs[uitableplan.active_room] !== undefined) {
                        uitableplan.button.add({
                            displaytext: "✕",
                            background: ['#ff0000', '#cc000a'], foreground: '#000000', border: '#ff0000', border_width: 3, grd_type: 'vertical',
                            x: uitableplan.x + uitableplan.width - 540, y: uitableplan.y + uitableplan.height - 60, width: 50, height: 50, border_radius: 5, font_size: 30, hover_border: '#cc000a',
                            callback: () => {
                                uitableplan.background_imgs[uitableplan.active_room] = undefined;
                                this.update();
                            },
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
                if (uitableplan.background_imgs[uitableplan.active_room] !== undefined) {
                    ctx.drawImage(uitableplan.background_imgs[uitableplan.active_room], uitableplan.x, uitableplan.y, uitableplan.width - 225, uitableplan.height - this.bottom_bar_height);
                }
                if (uitableplan.grid_active && uitableplan.editable) {
                    for (var j = 0; j < this.horizontal_lines_count; j++) {
                        //draw horizontal lines
                        if (j % 2 == 0) {
                            ctx.strokeStyle = '#000000';
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            var y = j * uitableplan.distance + uitableplan.y
                            ctx.moveTo(uitableplan.x, y);
                            ctx.lineTo(uitableplan.x + uitableplan.width - 225, y);
                        }
                        else {
                            ctx.strokeStyle = '#000000A9';
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            var y = j * uitableplan.distance + uitableplan.y
                            ctx.moveTo(uitableplan.x, y);
                            ctx.lineTo(uitableplan.x + uitableplan.width - 225, y);
                        }
                        ctx.stroke();
                    }
                    for (var j = 0; j < (uitableplan.width - 225) / uitableplan.distance; j++) {
                        //draw vertical lines
                        if (j % 2 == 0) {
                            ctx.strokeStyle = '#000000';
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            var x = j * uitableplan.distance + uitableplan.x;
                            ctx.moveTo(x, uitableplan.y);
                            ctx.lineTo(x, uitableplan.y + uitableplan.height - this.bottom_bar_height);
                        }
                        else {
                            ctx.strokeStyle = '#000000A9';
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            var x = j * uitableplan.distance + uitableplan.x
                            ctx.moveTo(x, uitableplan.y);
                            ctx.lineTo(x, uitableplan.y + uitableplan.height - this.bottom_bar_height);
                        }
                        ctx.stroke();
                    }
                }
                ctx.lineWidth = uitableplan.border_width;
                ctx.strokeStyle = uitableplan.border;
                ctx.strokeRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
                uitableplan.dragndrop.render(ctx);
                if (uitableplan.draw.mousedown_x != null) {
                    if (uitableplan.rect) {
                        ctx.fillStyle = '#0000FF';
                        ctx.strokeStyle = '#0579ff';
                        ctx.lineWidth = 3;
                        ctx.fillRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                            uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                        ctx.strokeRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                            uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                    }
                    else if (uitableplan.circle) {
                        ctx.beginPath();
                        ctx.fillStyle = '#0000FF';
                        ctx.strokeStyle = '#0579ff';
                        ctx.lineWidth = 3;
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
                        ctx.stroke();

                    }
                    else if (uitableplan.image) {
                        if (uitableplan.nextImage !== undefined) {
                            ctx.strokeStyle = '#0579ff';
                            ctx.lineWidth = 3;
                            ctx.drawImage(uitableplan.nextImage, uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                                uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                            ctx.strokeRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                                uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                        }
                    }
                    else if (uitableplan.text_label) {
                        var x = uitableplan.draw.mousedown_x + uitableplan.x;
                        var y = uitableplan.draw.mousedown_y + uitableplan.y;
                        var width = uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x;
                        var height = uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y;
                        if (width < 0) {
                            x = uitableplan.draw.mousemove_x + uitableplan.x;
                            width = uitableplan.draw.mousedown_x + uitableplan.x - x;
                        }
                        if (height < 0) {
                            y = uitableplan.draw.mousemove_y + uitableplan.y;
                            height = uitableplan.draw.mousedown_y + uitableplan.y - y;
                        }
                        ctx.font = height + 'px Everson Mono';
                        ctx.fillStyle = '#0000FF';
                        ctx.strokeStyle = '#0579ff';
                        ctx.lineWidth = 1;
                        var text_width = ctx.measureText(uitableplan.text_label_displaytext).width;
                        if (text_width > width) {
                            ctx.fillText(uitableplan.text_label_displaytext, x, y + (height / 2) + height / 3.3, width);
                            ctx.strokeText(uitableplan.text_label_displaytext, x, y + (height / 2) + height / 3.3, width);
                        }
                        else {
                            ctx.fillText(uitableplan.text_label_displaytext, x + (width - text_width) / 2, y + (height / 2) + height / 3.3);
                            ctx.strokeText(uitableplan.text_label_displaytext, x + (width - text_width) / 2, y + (height / 2) + height / 3.3)
                        }

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
                if (uitableplan.image) {
                    var button = uitableplan.button.find('image');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('image');
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
                if (uitableplan.text_label) {
                    var button = uitableplan.button.find('text label');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('text label');
                    if (button !== undefined) {
                        button.border = '#4fbcff';
                        button.hover_border = '#009dff';
                    }
                }
                if (uitableplan.change_frame_color) {
                    var button = uitableplan.button.find('frame color');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('frame color');
                    if (button !== undefined) {
                        button.border = '#4fbcff';
                        button.hover_border = '#009dff';
                    }
                }
                if (uitableplan.change_background_color) {
                    var button = uitableplan.button.find('background color');
                    if (button !== undefined) {
                        button.border = '#ffffff';
                        button.hover_border = '#ffffff';
                    }
                }
                else {
                    var button = uitableplan.button.find('background color');
                    if (button !== undefined) {
                        button.border = '#4fbcff';
                        button.hover_border = '#009dff';
                    }
                }
                uitableplan.button.render(ctx);
                uitableplan.numpad.render(ctx);
                uitableplan.checkbox.render(ctx);

                uitableplan.textbox.render(ctx);
                uitableplan.textinput.render(ctx);
                uitableplan.colorpalet.render(ctx);
                uitableplan.buttonrow.render(ctx);
                uitableplan.dialog.render(ctx);
            }
        }

    }
    onClick(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (!uitableplan.inputButtonRowDisabled) {
                uitableplan.buttonrow.onClick(x, y);
            }
            uitableplan.dialog.onClick(x, y);
            if (!uitableplan.inputDisabled) {
                uitableplan.dragndrop.onClick(x, y);
                uitableplan.colorpalet.onClick(x, y);
                uitableplan.button.onClick(x, y);
                uitableplan.numpad.onClick(x, y);
                uitableplan.checkbox.onClick(x, y);
                uitableplan.textinput.onClick(x, y);

            }
        }
    }
    fileHandler(input) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (!uitableplan.inputDisabled) {
                uitableplan.button.fileHandler(input);
            }
        }
    }
    onMouseDown(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (!uitableplan.inputButtonRowDisabled) {
                uitableplan.buttonrow.onMouseDown(x, y);
            }
            uitableplan.dialog.onMouseDown(x, y);
            if (!uitableplan.inputDisabled) {
                uitableplan.button.onMouseDown(x, y);
                uitableplan.colorpalet.onMouseDown(x, y);
                uitableplan.numpad.onMouseDown(x, y);
                uitableplan.checkbox.onMouseDown(x, y);
                uitableplan.textinput.onMouseDown(x, y);
                uitableplan.dragndrop.onMouseDown(x, y);

                if (!uitableplan.circle && !uitableplan.rect && !uitableplan.image && !uitableplan.text_label && uitableplan.editable) {
                }
                if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true || uitableplan.image == true || uitableplan.text_label == true)) {
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
                if (!uitableplan.inputButtonRowDisabled) {
                    uitableplan.buttonrow.onMouseUp(x, y);
                }
                if (!uitableplan.inputDisabled) {
                    if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true || uitableplan.image == true || uitableplan.text_label == true) && uitableplan.draw.mousedown_x != null) {
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
                                background: ['#0000FF'], foreground: '#ffffff', border: '#0579ff', border_width: 3, grd_type: 'vertical', active: uitableplan.active, distance: uitableplan.distance, grid_active: uitableplan.grid_active,
                                x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked, edit_mode: uitableplan.editable,
                            });
                            uitableplan.addToUndoable();
                        }
                        else if (uitableplan.circle) {
                            uitableplan.dragndrop.add({
                                displaytext: '', group_id: uitableplan.active_room, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - this.bottom_bar_height,
                                background: ['#0000FF'], foreground: '#ffffff', border: '#0579ff', border_width: 3, grd_type: 'vertical',  type: 'circle', active: uitableplan.active, distance: uitableplan.distance, grid_active: uitableplan.grid_active,
                                x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked, edit_mode: uitableplan.editable,
                            });
                            uitableplan.addToUndoable();
                        }
                        else if (uitableplan.image) {
                            uitableplan.dragndrop.add({
                                nextImage: uitableplan.nextImage,
                                displaytext: '', group_id: uitableplan.active_room, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - this.bottom_bar_height,
                                background: ['#0000FF'], foreground: '#ffffff', border: '#0579ff', border_width: 3, grd_type: 'vertical',  type: 'image', active: uitableplan.active, distance: uitableplan.distance, grid_active: uitableplan.grid_active,
                                x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, callback: uitableplan.tableClicked, edit_mode: uitableplan.editable,
                            });
                            uitableplan.addToUndoable();
                        }
                        else if (uitableplan.text_label) {
                            uitableplan.dragndrop.add({
                                displaytext: uitableplan.text_label_displaytext, group_id: uitableplan.active_room, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - this.bottom_bar_height,
                                background: ['#0000FF'], foreground: '#000000', border: '#0579ff', border_width: 1, grd_type: 'vertical',  type: 'text', active: uitableplan.active, distance: uitableplan.distance, grid_active: uitableplan.grid_active,
                                x: x, y: y, width: width, height: height, font_size: 25, angle: 0, addToUndoable: uitableplan.addToUndoable, isSelected: uitableplan.isSelected, edit_mode: uitableplan.editable,
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
                    uitableplan.checkbox.onMouseUp(x, y);
                    uitableplan.textinput.onMouseUp(x, y);
                }
                uitableplan.dialog.onMouseUp(x, y);
            }
        }

    }
    onMouseMove(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.active) {
                if (!uitableplan.inputButtonRowDisabled) {
                    uitableplan.buttonrow.onMouseMove(x, y);
                }
                uitableplan.dialog.onMouseMove(x, y);
                if (!uitableplan.inputDisabled) {
                    uitableplan.button.onMouseMove(x, y);
                    uitableplan.colorpalet.onMouseMove(x, y);
                    uitableplan.numpad.onMouseMove(x, y);
                    uitableplan.checkbox.onMouseMove(x, y);
                    if (uitableplan.select) {
                        uitableplan.dragndrop.onMouseMove(x, y);
                    }
                    if (uitableplan.selected) {
                        var [x_corners, y_corners] = uitableplan.dragndrop.calculateCornerPositions(uitableplan.selected.x, uitableplan.selected.y, uitableplan.selected.width, uitableplan.selected.height, uitableplan.selected.angle);
                        var min_x_corner = x_corners[0];
                        if (Math.round(min_x_corner - uitableplan.x) >= 0 && uitableplan.dragndrop.mouse_down) {
                            uitableplan.textinput.find('posx').setText(String(Math.round(min_x_corner - uitableplan.x)));
                        }
                        var min_y_corner = y_corners[0];
                        if (Math.round(min_y_corner - uitableplan.y) >= 0 && uitableplan.dragndrop.mouse_down) {
                            uitableplan.textinput.find('posy').setText(String(Math.round(min_y_corner - uitableplan.y)));
                        }
                        var height = uitableplan.selected.height;
                        var width = uitableplan.selected.width;
                        var angle = uitableplan.selected.angle;
                        if (uitableplan.dragndrop.mouse_down) {
                            uitableplan.textinput.find('height').setText(String(Math.round(height)));
                            uitableplan.textinput.find('width').setText(String(Math.round(width)));
                            if (Math.abs(Math.round(angle)) <= 360) {
                                uitableplan.textinput.find('angle').setText(String(Math.abs(Math.round(angle))));
                            }
                        }
                    }
                    else if (uitableplan.rect || uitableplan.circle || uitableplan.image || uitableplan.text_label) {
                        $(this.canvas).css('cursor', 'crosshair');
                    }
                    uitableplan.textinput.onMouseMove(x, y);
                    if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true || uitableplan.image == true || uitableplan.text_label == true)) {
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
            if (!uitableplan.inputButtonRowDisabled) {
                uitableplan.buttonrow.onKeyDown(e);
            }
            uitableplan.dialog.onKeyDown(e);
            if (!uitableplan.inputDisabled) {
                uitableplan.button.onKeyDown(e);
                uitableplan.numpad.onKeyDown(e);
                uitableplan.textinput.onKeyDown(e);
            }
        }
    }
    onKeyUp(e) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (!uitableplan.inputButtonRowDisabled) {
                uitableplan.buttonrow.onKeyUp(e);
            }
            uitableplan.dialog.onKeyUp(e);
            if (!uitableplan.inputDisabled) {
                uitableplan.textinput.onKeyUp(e);
            }
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
            uitableplan.checkbox.clear();
            uitableplan.textbox.clear();
            uitableplan.textinput.clear();
            uitableplan.dialog.clear();
        }
    }
}
