class UIDragNDrop {
    constructor(canvas) {
        this.textbox = new UITextBox(canvas);
        this.circle = new UICircle(canvas);
        this.dragndrops = [];
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
        this.box_size = 22;
        this.box_size_half = this.box_size / 2;
        this.canvas = canvas;
    }
    add(options) {
        options.selected = false;
        options.resizeable = false;
        options.center_x = options.x + options.width / 2;
        options.center_y = options.y + options.height / 2;
        options.resizedirection = '';
        options.changed = true;
        options.mouse_down_action = '';
        options.moveable = false;
        options.change = () => {
            options.changed = true;
            this.changeHandler(options);
        }
        this.dragndrops.push(options);
        if (options.type == 'circle') {
            this.circle.add(options);
        }
        else {
            this.textbox.add(options);
        }
        return options;
    }
    render(ctx) {
        for (var j in this.dragndrops) {

            var dragndrop = this.dragndrops[j];
            if (dragndrop.type == 'circle') {
                this.circle.circles = [dragndrop];
                this.circle.render(ctx);

            }
            else {
                this.textbox.textboxes = [dragndrop];
                this.textbox.render(ctx);

            }
        }
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.editable == true && dragndrop.selected == true) {
                ctx.save(); //saves the state of canvas
                ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

                ctx.translate(dragndrop.center_x, dragndrop.center_y);
                ctx.rotate(dragndrop.angle * Math.PI / 180);
                ctx.translate(-dragndrop.center_x, -dragndrop.center_y)
                ctx.strokeStyle = 'black';
                ctx.lineWidth = dragndrop.border_width * 1.5;
                ctx.fillStyle = 'black';
                ctx.beginPath();
                ctx.rect(dragndrop.x, dragndrop.y, dragndrop.width, dragndrop.height);
                ctx.stroke();
                ctx.strokeStyle = 'white';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.rect(dragndrop.x - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size);
                ctx.rect(dragndrop.x - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size);
                ctx.rect(dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size);
                ctx.rect(dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(dragndrop.x + dragndrop.width / 2, dragndrop.y - this.box_size_half * 3, this.box_size_half, 0, 2 * Math.PI);
                ctx.fill();

                ctx.beginPath();
                ctx.strokeStyle = 'black';
                ctx.moveTo(dragndrop.x + dragndrop.width / 2, dragndrop.y);
                ctx.lineTo(dragndrop.x + dragndrop.width / 2, dragndrop.y - this.box_size_half * 3);
                ctx.stroke();
                ctx.strokeStyle = 'white';
                ctx.beginPath();

                if (dragndrop.width > 2 * this.box_size) {
                    ctx.rect(dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size);
                    ctx.rect(dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size);
                }
                if (dragndrop.height > 2 * this.box_size) {
                    ctx.rect(dragndrop.x - this.box_size_half, dragndrop.y + dragndrop.height / 2 - this.box_size_half, this.box_size, this.box_size);
                    ctx.rect(dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y + dragndrop.height / 2 - this.box_size_half, this.box_size, this.box_size);
                }
                ctx.stroke();
                ctx.fill();
                ctx.restore(); //restore the state of canvas
            }
        }

    }
    setEditable(group_id, state) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.group_id == group_id) {
                dragndrop.editable = state;
                if (!state) {
                    dragndrop.selected = false;
                }
            }
        }
    }
    deleteSelected(group_id) {
        //one gruop id per table plan

        this.circle.clear();
        this.textbox.clear();
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.selected && dragndrop.group_id == group_id) {
                this.dragndrops.splice(i, 1);
                var undoable = []
                for (var j in this.dragndrops) {
                    if (dragndrop.type == 'circle') {
                        this.circle.add({ ...dragndrop });
                    }
                    else {
                        this.textbox.add({ ...dragndrop });
                    }
                    if (group_id == this.dragndrops[j].group_id) {
                        undoable.push({ ...this.dragndrops[j] });
                    }
                }
                dragndrop.addToUndoable(undoable);
            }
        }
    }
    replaceElementsByGropID(group_id, elementList) {
        var new_dragndrops = [];
        var editable = null;
        this.circle.clear();
        this.textbox.clear();

        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.group_id != group_id) {
                new_dragndrops.push({ ...dragndrop });
                if (dragndrop.type == 'circle') {
                    this.circle.add({ ...dragndrop });
                }
                else {
                    this.textbox.add({ ...dragndrop });
                }
            }
            else if (editable == null) {
                editable = dragndrop.editable;
            }
        }

        for (var i in elementList) {
            var dragndrop = elementList[i];
            if (dragndrop.selected) {
                dragndrop.isSelected(dragndrop);
            }else{
                dragndrop.isSelected(null);
            }
            dragndrop.editable = editable;
            new_dragndrops.push({ ...dragndrop });
            if (dragndrop.type == 'circle') {
                this.circle.add({ ...dragndrop });
            }
            else {
                this.textbox.add({ ...dragndrop });
            }
        }
        this.dragndrops = new_dragndrops;
    }
    loadSaved(group_id, elementList) {
        var new_dragndrops = [];
        var editable = null;
        this.circle.clear();
        this.textbox.clear();

        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.group_id != group_id) {
                new_dragndrops.push({ ...dragndrop });
                if (dragndrop.type == 'circle') {
                    this.circle.add({ ...dragndrop });
                }
                else {
                    this.textbox.add({ ...dragndrop });
                }
            }
            else if (editable == null) {
                editable = dragndrop.editable;
            }
        }
        this.dragndrops = new_dragndrops;
        for (var i in elementList) {
            var dragndrop = elementList[i];
            dragndrop.editable = editable;
            this.add({ ...dragndrop });
        }
    }
    onClick(x, y) {
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            var startx = dragndrop.x;
            var starty = dragndrop.y;
            var endx = startx + dragndrop.width;
            var endy = starty + dragndrop.height;
            var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);
            if (nx >= startx && nx <= endx && ny >= starty && ny <= endy) {
                if (dragndrop.type == 'circle') {
                    var mouse_relative_center_x = nx - dragndrop.center_x;
                    var mouse_relative_center_y = ny - dragndrop.center_y;
                    var angle = Math.atan2(mouse_relative_center_x, mouse_relative_center_y) + Math.PI / 2;
                    var a = dragndrop.width / 2;
                    var b = dragndrop.height / 2;
                    var radius = (a * b) / Math.sqrt(a ** 2 * Math.sin(angle) ** 2 + b ** 2 * Math.cos(angle) ** 2); // calculates radius at given angle
                    var center_distance = Math.abs(mouse_relative_center_x / Math.cos(angle));
                    if (center_distance < radius) {
                        dragndrop.callback(dragndrop.displaytext);
                    }
                }
                else {
                    dragndrop.callback(dragndrop.displaytext);
                }
            }
        }
    }
    onMouseDown(x, y) {
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);
            [dragndrop.center_x, dragndrop.center_y] = rotate(dragndrop.center_x, dragndrop.center_y, dragndrop.x + dragndrop.width / 2, dragndrop.y + dragndrop.height / 2, -dragndrop.angle);
            dragndrop.x = dragndrop.center_x - dragndrop.width / 2;
            dragndrop.y = dragndrop.center_y - dragndrop.height / 2;
            var startx = dragndrop.x;
            var starty = dragndrop.y;
            var endx = startx + dragndrop.width;
            var endy = starty + dragndrop.height;
            if (dragndrop.resizeable && dragndrop.editable && dragndrop.selected) {
                this.mouse_down = true;
                this.array_move(this.dragndrops, i, this.dragndrops.length - 1);
                this.mouse_down_x = x - startx;
                this.mouse_down_y = y - starty;
                dragndrop.mouse_down_action = dragndrop.resizedirection;

                //Neu berechnung von center nach größen änderung
                [dragndrop.center_x, dragndrop.center_y] = rotate(dragndrop.center_x, dragndrop.center_y, dragndrop.x + dragndrop.width / 2, dragndrop.y + dragndrop.height / 2, -dragndrop.angle);
                dragndrop.x = dragndrop.center_x - dragndrop.width / 2;
                dragndrop.y = dragndrop.center_y - dragndrop.height / 2;
                return;
            }
            else {
                dragndrop.mouse_down_action = '';
            }
            if (nx >= startx && nx <= endx && ny >= starty && ny <= endy) {
                dragndrop.selected = true;
                dragndrop.isSelected(dragndrop);
                var g_id = dragndrop.group_id;
                for (var j = this.dragndrops.length - 1; j >= 0; j--) {
                    var s_dragndrop = this.dragndrops[j];
                    if (s_dragndrop.group_id == g_id && j != i) {
                        s_dragndrop.selected = false;
                    }
                }
                this.mouse_down = true;
                this.array_move(this.dragndrops, i, this.dragndrops.length - 1);


                this.mouse_down_x = x - startx;
                this.mouse_down_y = y - starty;

                triggerRepaint();
                return;
            }
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            if (x > dragndrop.contain_x && x < dragndrop.contain_x + dragndrop.contain_width &&
                y > dragndrop.contain_y && y < dragndrop.contain_y + dragndrop.contain_height) {
                dragndrop.selected = false;
                dragndrop.isSelected(null);
            }

        }
        triggerRepaint();
        return;
    }
    changeHandler(dragndrop) {
        if (dragndrop.changed) {
            var group_id = dragndrop.group_id;
            dragndrop.changed = false;
            var undoable = []
            for (var j in this.dragndrops) {
                if (group_id == this.dragndrops[j].group_id) {
                    undoable.push({ ...this.dragndrops[j] });
                }
            }
            dragndrop.addToUndoable(undoable);
        }
    }
    onMouseUp(x, y) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            [dragndrop.center_x, dragndrop.center_y] = rotate(dragndrop.center_x, dragndrop.center_y, dragndrop.x + dragndrop.width / 2, dragndrop.y + dragndrop.height / 2, -dragndrop.angle);
            dragndrop.x = dragndrop.center_x - dragndrop.width / 2;
            dragndrop.y = dragndrop.center_y - dragndrop.height / 2;
            this.changeHandler(dragndrop);
            dragndrop.mouse_down_action = '';
        }
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
    setCursorAtLocation(mouse_x, mouse_y, x, y, width, height, cursor_type, object) {
        var x1 = x + width;
        var y1 = y + height;
        if (mouse_x >= x && mouse_x <= x1 && mouse_y >= y && mouse_y <= y1) {
            $(this.canvas).css('cursor', cursor_type);
            object.resizeable = true;
            object.resizedirection = cursor_type;
            return;
        }
    }
    calculateCornerPositions(x, y, width, height, angle, sort_x, sort_y) {
        var [corners_x, corners_y] = this.calculateUnsortedCornerPositions(x, y, width, height, angle);
        //retruns sorted corner positions
        if (sort_x || sort_x == undefined) {
            corners_x.sort(function (a, b) { return a - b });
        }
        if (sort_y || sort_y == undefined) {
            corners_y.sort(function (a, b) { return a - b });
        }
        return [corners_x, corners_y];
    }
    calculateUnsortedCornerPositions(x, y, width, height, angle) {
        var center_x = x + width / 2
        var center_y = y + height / 2

        var corners_x = [rotate(center_x, center_y, x, y, angle)[0], rotate(center_x, center_y, x + width, y, angle)[0],
        rotate(center_x, center_y, x + width, y + height, angle)[0], rotate(center_x, center_y, x, y + height, angle)[0]];

        var corners_y = [rotate(center_x, center_y, x + width, y + height, angle)[1], rotate(center_x, center_y, x, y + height, angle)[1],
        rotate(center_x, center_y, x, y, angle)[1], rotate(center_x, center_y, x + width, y, angle)[1]];

        //retruns sorted corner positions
        return [corners_x, corners_y];
    }
    onMouseMove(x, y) {
        if (this.mouse_down) {
            var dragndrop = this.dragndrops[this.dragndrops.length - 1];
            var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);

            //when mouse is down on drag and drop item
            if (dragndrop.mouse_down_action != '' && dragndrop.editable == true && dragndrop.selected) {
                //when button (resize) is pressed
                $(this.canvas).css('cursor', dragndrop.mouse_down_action);
                var new_height = dragndrop.height;
                var new_width = dragndrop.width;
                var new_x = dragndrop.x;
                var new_y = dragndrop.y;
                if (dragndrop.mouse_down_action == 's-resize' || dragndrop.mouse_down_action == 'se-resize' || dragndrop.mouse_down_action == 'sw-resize') {
                    new_height = ny - dragndrop.y;
                    if (new_height <= this.box_size + 2) {
                        new_height = this.box_size + 2;
                    }
                }
                if (dragndrop.mouse_down_action == 'e-resize' || dragndrop.mouse_down_action == 'ne-resize' || dragndrop.mouse_down_action == 'se-resize') {
                    new_width = nx - dragndrop.x;
                    if (new_width <= this.box_size + 2) {
                        new_width = this.box_size + 2;
                    }
                }
                if (dragndrop.mouse_down_action == 'n-resize' || dragndrop.mouse_down_action == 'ne-resize' || dragndrop.mouse_down_action == 'nw-resize') {
                    new_y = ny;
                    new_height = dragndrop.height + (dragndrop.y - ny);
                    if (new_height <= this.box_size + 2) {
                        new_y = new_y - (this.box_size + 2 - new_height);
                        new_height = this.box_size + 2;
                    }
                }
                if (dragndrop.mouse_down_action == 'w-resize' || dragndrop.mouse_down_action == 'nw-resize' || dragndrop.mouse_down_action == 'sw-resize') {
                    new_x = nx;
                    new_width = dragndrop.width + (dragndrop.x - nx);
                    if (new_width <= this.box_size + 2) {
                        new_x = new_x - (this.box_size + 2 - new_width);
                        new_width = this.box_size + 2;
                    }
                }
                var dragndropnoref = { ...this.dragndrops[this.dragndrops.length - 1] };
                dragndropnoref.width = new_width;
                dragndropnoref.height = new_height;

                dragndropnoref.x = new_x;
                dragndropnoref.y = new_y;
                [dragndropnoref.center_x, dragndropnoref.center_y] = rotate(dragndropnoref.center_x, dragndropnoref.center_y, dragndropnoref.x + dragndropnoref.width / 2, dragndropnoref.y + dragndropnoref.height / 2, -dragndropnoref.angle);
                dragndropnoref.x = dragndropnoref.center_x - dragndropnoref.width / 2;
                dragndropnoref.y = dragndropnoref.center_y - dragndropnoref.height / 2;
                if (dragndropnoref.mouse_down_action == 'crosshair') {
                    var mouse_relative_center_x = x - dragndropnoref.center_x;
                    var mouse_relative_center_y = y - dragndropnoref.center_y;
                    var result = Math.atan2(mouse_relative_center_x, mouse_relative_center_y);
                    var angle = -180 - (result * 180) / Math.PI;
                    dragndropnoref.angle = angle;
                }
                var [x_corners, y_corners] = this.calculateCornerPositions(dragndropnoref.x, dragndropnoref.y, dragndropnoref.width, dragndropnoref.height, dragndropnoref.angle);
                var max_y_corner = y_corners[3];
                var min_y_corner = y_corners[0];
                var max_x_corner = x_corners[3];
                var min_x_corner = x_corners[0];
                if (max_y_corner <= dragndrop.contain_y + dragndrop.contain_height && min_y_corner >= dragndrop.contain_y && min_x_corner >= dragndrop.contain_x && max_x_corner <= dragndrop.contain_x + dragndrop.contain_width) {
                    dragndrop.changed = true;
                    dragndrop.width = new_width;
                    dragndrop.height = new_height;
                    dragndrop.x = new_x;
                    dragndrop.y = new_y;
                    [dragndrop.center_x, dragndrop.center_y] = rotate(dragndrop.center_x, dragndrop.center_y, dragndrop.x + dragndrop.width / 2, dragndrop.y + dragndrop.height / 2, -dragndrop.angle);
                    dragndrop.x = dragndrop.center_x - dragndrop.width / 2;
                    dragndrop.y = dragndrop.center_y - dragndrop.height / 2;
                    if (dragndrop.mouse_down_action == 'crosshair') {
                        var mouse_relative_center_x = x - dragndrop.center_x;
                        var mouse_relative_center_y = y - dragndrop.center_y;
                        var result = Math.atan2(mouse_relative_center_x, mouse_relative_center_y);
                        var angle = -180 - (result * 180) / Math.PI;
                        dragndrop.angle = angle;
                    }
                }

            }
            else {
                $(this.canvas).css('cursor', 'move');
                var new_top_left_x = x - this.mouse_down_x;
                var new_top_left_y = y - this.mouse_down_y;
                var [x_corners, y_corners] = this.calculateCornerPositions(new_top_left_x, new_top_left_y, dragndrop.width, dragndrop.height, dragndrop.angle);
                var center_x = (x_corners[0] + x_corners[1] + x_corners[2] + x_corners[3]) / 4
                var center_y = (y_corners[0] + y_corners[1] + y_corners[2] + y_corners[3]) / 4

                var min_x_corner = x_corners[0];
                var max_x_corner = x_corners[3];

                var min_y_corner = y_corners[0];
                var max_y_corner = y_corners[3];

                if (min_x_corner < dragndrop.contain_x) {
                    var offset = center_x - min_x_corner - dragndrop.width / 2;
                    new_top_left_x = offset + dragndrop.contain_x;
                }
                if (max_x_corner > dragndrop.contain_x + dragndrop.contain_width) {
                    var offset = max_x_corner - center_x - dragndrop.width / 2;
                    new_top_left_x = dragndrop.contain_x - offset + dragndrop.contain_width - dragndrop.width;
                }
                if (min_y_corner < dragndrop.contain_y) {
                    var offset = center_y - min_y_corner - dragndrop.height / 2;
                    new_top_left_y = offset + dragndrop.contain_y;
                }
                if (max_y_corner > dragndrop.contain_y + dragndrop.contain_height) {
                    var offset = max_y_corner - center_y - dragndrop.height / 2;
                    new_top_left_y = dragndrop.contain_y - offset + dragndrop.contain_height - dragndrop.height;
                }
                dragndrop.x = new_top_left_x;
                dragndrop.y = new_top_left_y;
                dragndrop.center_x = dragndrop.x + dragndrop.width / 2;
                dragndrop.center_y = dragndrop.y + dragndrop.height / 2;
                dragndrop.changed = true;
            }
            triggerRepaint();
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);
            var startx = dragndrop.x;
            var starty = dragndrop.y;
            var endx = startx + dragndrop.width;
            var endy = starty + dragndrop.height;
            dragndrop.resizeable = false;
            dragndrop.moveable = false;
            if (nx >= startx && nx <= endx && ny >= starty && ny <= endy && dragndrop.mouse_down_action == '') {
                $(this.canvas).css('cursor', 'move');
                dragndrop.moveable = true;
            }
            if (dragndrop.editable && dragndrop.selected) {
                //dragndrop.editable allows resizing
                this.setCursorAtLocation(nx, ny, dragndrop.x - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size, "nw-resize", dragndrop);
                this.setCursorAtLocation(nx, ny, dragndrop.x - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size, "sw-resize", dragndrop);
                this.setCursorAtLocation(nx, ny, dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size, "ne-resize", dragndrop);
                this.setCursorAtLocation(nx, ny, dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size, "se-resize", dragndrop);
                this.setCursorAtLocation(nx, ny, dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y - this.box_size * 2, this.box_size, this.box_size, "crosshair", dragndrop);

                if (dragndrop.width > 2 * this.box_size) {
                    this.setCursorAtLocation(nx, ny, dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size, "n-resize", dragndrop);
                    this.setCursorAtLocation(nx, ny, dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size, "s-resize", dragndrop);
                }
                if (dragndrop.height > 2 * this.box_size) {
                    this.setCursorAtLocation(nx, ny, dragndrop.x - this.box_size_half, dragndrop.y + dragndrop.height / 2 - this.box_size_half, this.box_size, this.box_size, "w-resize", dragndrop);
                    this.setCursorAtLocation(nx, ny, dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y + dragndrop.height / 2 - this.box_size_half, this.box_size, this.box_size, "e-resize", dragndrop);
                }
            }
            if (dragndrop.moveable || dragndrop.resizeable) {
                return;
            }
        }
        $(this.canvas).css('cursor', 'default');
        return;
    }
    find(name) {
        return;
    }
    clear() {

        this.textbox.clear();
        this.circle.clear();
        this.dragndrops = [];
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
    }
}