class UIDragNDrop {
    constructor(canvas) {
        this.textbox = new UITextBox(canvas);
        this.circle = new UICircle(canvas);
        this.image = new UIImage(canvas);
        this.text = new UIText(canvas);
        this.dragndrops = [];
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
        this.box_size = 23;
        this.box_size_half = this.box_size / 2;
        this.canvas = canvas;
    }
    add(options) {
        options.drawVerticalLine = '';
        options.drawHorizontalLine = '';
        options.highlight = false;
        options.selected = false;
        options.resizeable = false;
        options.center_x = options.x + options.width / 2;
        options.center_y = options.y + options.height / 2;
        options.resizedirection = '';
        options.changed = false;
        options.mouse_down_action = '';
        options.moveable = false;
        options.mouse_down_on = false;

        if (options.angle === undefined) {
            options.angle = 0;
        }
        if (options.active === undefined) {
            options.active = true;
        }
        if (options.editable === undefined) {
            options.editable = false;
        }
        if (options.contain_x === undefined) {
            options.contain_x = 0;
        }
        if (options.contain_y === undefined) {
            options.contain_y = 0;
        }
        if (options.contain_width === undefined) {
            options.contain_width = this.canvas.width - options.contain_x;
        }
        if (options.contain_height === undefined) {
            options.contain_height = this.canvas.height - options.contain_y;
        }
        options.setActive = (state) => {
            options.active = state;
        };
        options.setHighlight = (state) => { //highlight when table active
            options.highlight = state;
        }
        options.setMainHighlight = (number) => { //highlight when table active
            options.main_highlight = number;
        }
        options.change = () => {
            if (options.addToUndoable !== undefined) {
                options.changed = true;
                this.changeHandler(options);
            }
        }
        this.dragndrops.push(options);
        if (options.type == 'circle') {
            this.circle.add(options);
        }
        else if (options.type == 'image') {
            this.image.add(options);
        }
        else if (options.type == 'text') {
            this.text.add(options);
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
            else if (dragndrop.type == 'image') {
                this.image.images = [dragndrop];
                this.image.render(ctx);
            }
            else if (dragndrop.type == 'text') {
                this.text.texts = [dragndrop];
                this.text.render(ctx);
            }
            else {
                this.textbox.textboxes = [dragndrop];
                this.textbox.render(ctx);
            }
        }
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {
                if (dragndrop.editable == true && dragndrop.selected == true) {
                    ctx.save(); //saves the state of canvas
                    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
                    ctx.translate(dragndrop.center_x, dragndrop.center_y);
                    ctx.rotate(dragndrop.angle * Math.PI / 180);
                    ctx.translate(-dragndrop.center_x, -dragndrop.center_y)
                    ctx.strokeStyle = 'black';
                    ctx.lineWidth = 2;
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
                    ctx.stroke();
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
                    ctx.fill();
                    ctx.stroke();
                    ctx.restore(); //restore the state of canvas
                    if (dragndrop.moveable == true) {
                        var [x_corners, y_corners] = this.calculateCornerPositions(dragndrop.x, dragndrop.y, dragndrop.width, dragndrop.height, dragndrop.angle);
                        ctx.strokeStyle = 'red';
                        ctx.lineWidth = 2;
                        if (dragndrop.drawVerticalLine == 'back') {
                            ctx.beginPath();
                            ctx.moveTo(x_corners[3], dragndrop.contain_y)
                            ctx.lineTo(x_corners[3], dragndrop.contain_y + dragndrop.contain_height);
                            ctx.stroke();
                            ctx.fill();
                        } else if (dragndrop.drawVerticalLine == 'front') {
                            ctx.beginPath();
                            ctx.moveTo(x_corners[0], dragndrop.contain_y)
                            ctx.lineTo(x_corners[0], dragndrop.contain_y + dragndrop.contain_height);
                            ctx.stroke();
                            ctx.fill();
                        }
                        if (dragndrop.drawHorizontalLine == 'top') {
                            ctx.beginPath();
                            ctx.moveTo(dragndrop.contain_x, y_corners[0])
                            ctx.lineTo(dragndrop.contain_x + dragndrop.contain_width, y_corners[0]);
                            ctx.stroke();
                            ctx.fill();
                        } else if (dragndrop.drawHorizontalLine == 'bottom') {
                            ctx.beginPath();
                            ctx.moveTo(dragndrop.contain_x, y_corners[3])
                            ctx.lineTo(dragndrop.contain_x + dragndrop.contain_width, y_corners[3]);
                            ctx.stroke();
                            ctx.fill();
                        }
                    }
                }
            }
        }
    }
    setEditable(state) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            dragndrop.editable = state;
            if (!state) {
                dragndrop.selected = false;
            }
        }
    }
    setGrid(state, distance) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            dragndrop.grid_active = state;
            dragndrop.distance = distance;
        }
    }
    deleteSelected(group_id) {
        //one group id per table plan
        this.circle.clear();
        this.image.clear();
        this.text.clear();
        this.textbox.clear();
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {
                if (dragndrop.selected && dragndrop.group_id == group_id) {
                    this.dragndrops.splice(i, 1);
                    for (var j in this.dragndrops) {
                        if (dragndrop.type == 'circle') {
                            this.circle.add({ ...dragndrop });
                        }
                        else if (dragndrop.type == 'image') {
                            this.image.add({ ...dragndrop });
                        }
                        else {
                            this.textbox.add({ ...dragndrop });
                        }

                    }
                    dragndrop.addToUndoable();
                }
            }
        }
    }
    replaceElementsByGropID(group_id, elementList, active = false) {
        console.log('replaceElementsByGropID', group_id, elementList);
        var new_dragndrops = [];
        this.circle.clear();
        this.image.clear();
        this.text.clear();
        this.textbox.clear();

        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.group_id != group_id) {
                new_dragndrops.push({ ...dragndrop });
                if (dragndrop.type == 'circle') {
                    this.circle.add({ ...dragndrop });
                }
                else if (dragndrop.type == 'image') {
                    this.image.add({ ...dragndrop });
                }
                else if (dragndrop.type == 'text') {
                    this.text.add({ ...dragndrop });
                }
                else {
                    this.textbox.add({ ...dragndrop });
                }
            }
        }
        var selected = false;
        for (var i in elementList) {
            var dragndrop = elementList[i];
            if (active) {
                dragndrop.active = true;
            }
            new_dragndrops.push({ ...dragndrop });
            if (dragndrop.selected) {/////////////
                selected = true;
                dragndrop.isSelected(new_dragndrops[new_dragndrops.length - 1]);
            }
            if (dragndrop.type == 'circle') {
                this.circle.add({ ...dragndrop });
            }
            else if (dragndrop.type == 'image') {
                this.image.add({ ...dragndrop });
            }
            else if (dragndrop.type == 'text') {
                this.text.add({ ...dragndrop });
            }
            else {
                this.textbox.add({ ...dragndrop });
            }
        }
        if (selected == false && new_dragndrops.length > 0) {
            new_dragndrops[0].isSelected(null);
        }
        this.dragndrops = new_dragndrops;
        return new_dragndrops;
    }
    setActiveByGroupID(group_id, state) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.group_id == group_id) {
                dragndrop.active = state
            }
        }
    }
    loadSaved(elementList) {
        this.clear();
        for (var i in elementList) {
            var dragndrop = elementList[i];
            this.add({ ...dragndrop });
        }
    }
    onClick(x, y) {
        /*for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {

            }
        }*/
    }
    onMouseDown(x, y) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {
                var startx = dragndrop.x;
                var starty = dragndrop.y;
                var endx = startx + dragndrop.width;
                var endy = starty + dragndrop.height;
                var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);
                if (nx >= startx && nx <= endx && ny >= starty && ny <= endy) {
                    if (dragndrop.type == 'circle') {
                        //check if mouse is inside the circle
                        var mouse_relative_center_x = nx - dragndrop.center_x;
                        var mouse_relative_center_y = ny - dragndrop.center_y;
                        var angle = Math.atan2(mouse_relative_center_x, mouse_relative_center_y) + Math.PI / 2;
                        var a = dragndrop.width / 2;
                        var b = dragndrop.height / 2;
                        var radius = (a * b) / Math.sqrt(a ** 2 * Math.sin(angle) ** 2 + b ** 2 * Math.cos(angle) ** 2); // calculates radius at given angle
                        var center_distance = Math.abs(mouse_relative_center_x / Math.cos(angle));
                        if (center_distance < radius) {
                            dragndrop.mouse_down_on = true;
                        }
                    }
                    else if (dragndrop.type == 'image') {
                        dragndrop.mouse_down_on = true;
                    }
                    else if (dragndrop.type !== 'text') {
                        dragndrop.mouse_down_on = true;
                    }
                }
            }
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active && dragndrop.edit_mode && dragndrop.editable) {
                var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);
                [dragndrop.center_x, dragndrop.center_y] = (dragndrop.center_x, dragndrop.center_y, dragndrop.x + dragndrop.width / 2, dragndrop.y + dragndrop.height / 2, -dragndrop.angle);
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
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {
                if (x > dragndrop.contain_x && x < dragndrop.contain_x + dragndrop.contain_width &&
                    y > dragndrop.contain_y && y < dragndrop.contain_y + dragndrop.contain_height) {
                    dragndrop.selected = false;
                    dragndrop.isSelected(null);
                }
            }
        }
        triggerRepaint();
        return;
    }
    changeHandler(dragndrop) {
        if (dragndrop.changed) {
            dragndrop.changed = false;
            if (dragndrop.addToUndoable !== undefined) {
                dragndrop.addToUndoable();
            }
        }
    }
    onMouseUp(x, y) {
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {
                [dragndrop.center_x, dragndrop.center_y] = rotate(dragndrop.center_x, dragndrop.center_y, dragndrop.x + dragndrop.width / 2, dragndrop.y + dragndrop.height / 2, -dragndrop.angle);
                dragndrop.x = dragndrop.center_x - dragndrop.width / 2;
                dragndrop.y = dragndrop.center_y - dragndrop.height / 2;
                this.changeHandler(dragndrop);
                dragndrop.mouse_down_action = '';
                if (dragndrop.drawHorizontalLine !== '' || dragndrop.drawVerticalLine !== '') {
                    dragndrop.drawVerticalLine = '';
                    dragndrop.drawHorizontalLine = '';
                    triggerRepaint();
                }
                var startx = dragndrop.x;
                var starty = dragndrop.y;
                var endx = startx + dragndrop.width;
                var endy = starty + dragndrop.height;
                var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);
                if (nx >= startx && nx <= endx && ny >= starty && ny <= endy) {
                    if (dragndrop.type == 'circle') {
                        //check if mouse is on circle(ellipse)
                        var mouse_relative_center_x = nx - dragndrop.center_x;
                        var mouse_relative_center_y = ny - dragndrop.center_y;
                        var angle = Math.atan2(mouse_relative_center_x, mouse_relative_center_y) + Math.PI / 2;
                        var a = dragndrop.width / 2;
                        var b = dragndrop.height / 2;
                        var radius = (a * b) / Math.sqrt(a ** 2 * Math.sin(angle) ** 2 + b ** 2 * Math.cos(angle) ** 2); // calculates radius at given angle
                        var center_distance = Math.abs(mouse_relative_center_x / Math.cos(angle));
                        if (center_distance < radius && dragndrop.mouse_down_on == true) {
                            dragndrop.callback(dragndrop.displaytext);
                        }
                    }
                    else if (dragndrop.type == 'image' && dragndrop.mouse_down_on == true) {
                        dragndrop.callback(dragndrop.displaytext);
                    }
                    else if (dragndrop.type !== 'text' && dragndrop.mouse_down_on == true) {
                        dragndrop.callback(dragndrop.displaytext);
                    }
                }
                dragndrop.mouse_down_on = false;
            }
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
    calculateCornerPositions(x, y, width, height, angle, sort_x = undefined, sort_y = undefined) {
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
    snapAngle(angle) {
        var new_angle = Math.abs(angle);
        new_angle %= 45;
        if (new_angle >= 40) {
            return -(Math.round(Math.abs(angle) + 45 - new_angle));
        }
        else if (new_angle <= 5) {
            return -(Math.round(Math.abs(angle) - new_angle));
        }
        return angle
    }
    onMouseMove(x, y) {
        if (this.mouse_down) {
            var dragndrop = this.dragndrops[this.dragndrops.length - 1];
            if (dragndrop.active) {
                var [nx, ny] = rotate(dragndrop.center_x, dragndrop.center_y, x, y, dragndrop.angle);

                //when mouse is down on drag and drop item
                if (dragndrop.mouse_down_action != '' && dragndrop.editable == true && dragndrop.selected) {
                    //resize drag and drop item 
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
                    //code to prevent dragndrop from being resized outside of the container
                    dragndropnoref.width = new_width;
                    dragndropnoref.height = new_height;
                    dragndropnoref.x = new_x;
                    dragndropnoref.y = new_y;
                    [dragndropnoref.center_x, dragndropnoref.center_y] = rotate(dragndropnoref.center_x, dragndropnoref.center_y, dragndropnoref.x + dragndropnoref.width / 2, dragndropnoref.y + dragndropnoref.height / 2, -dragndropnoref.angle);
                    dragndropnoref.x = dragndropnoref.center_x - dragndropnoref.width / 2;
                    dragndropnoref.y = dragndropnoref.center_y - dragndropnoref.height / 2;

                    var [x_corners, y_corners] = this.calculateCornerPositions(dragndropnoref.x, dragndropnoref.y, dragndropnoref.width, dragndropnoref.height, dragndropnoref.angle);
                    var max_y_corner = y_corners[3];
                    var min_y_corner = y_corners[0];
                    var max_x_corner = x_corners[3];
                    var min_x_corner = x_corners[0];
                    if (max_y_corner <= dragndrop.contain_y + dragndrop.contain_height && min_y_corner >= dragndrop.contain_y && min_x_corner >= dragndrop.contain_x && max_x_corner <= dragndrop.contain_x + dragndrop.contain_width) {
                        //somehow the dragndrop is not being resized outside of the container
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
                            var snap_angle;
                            if (dragndrop.grid_active) {
                                snap_angle = this.snapAngle(angle)
                            }
                            var [x_corners, y_corners] = this.calculateCornerPositions(dragndrop.x, dragndrop.y, dragndrop.width, dragndrop.height, snap_angle);
                            var max_y_corner = y_corners[3];
                            var min_y_corner = y_corners[0];
                            var max_x_corner = x_corners[3];
                            var min_x_corner = x_corners[0];
                            if (max_y_corner <= dragndrop.contain_y + dragndrop.contain_height && min_y_corner >= dragndrop.contain_y && min_x_corner >= dragndrop.contain_x && max_x_corner <= dragndrop.contain_x + dragndrop.contain_width) {
                                dragndrop.angle = snap_angle;
                            } else {
                                [x_corners, y_corners] = this.calculateCornerPositions(dragndrop.x, dragndrop.y, dragndrop.width, dragndrop.height, angle);
                                max_y_corner = y_corners[3];
                                min_y_corner = y_corners[0];
                                max_x_corner = x_corners[3];
                                min_x_corner = x_corners[0];
                                if (max_y_corner <= dragndrop.contain_y + dragndrop.contain_height && min_y_corner >= dragndrop.contain_y && min_x_corner >= dragndrop.contain_x && max_x_corner <= dragndrop.contain_x + dragndrop.contain_width) {
                                    dragndrop.angle = angle;
                                }
                            }
                        }
                    }
                }
                else {
                    //handles mouse move when down on a dragndrop but not resizing
                    $(this.canvas).css('cursor', 'move');
                    var new_top_left_x = x - this.mouse_down_x;
                    var new_top_left_y = y - this.mouse_down_y;

                    var [x_corners, y_corners] = this.calculateCornerPositions(new_top_left_x, new_top_left_y, dragndrop.width, dragndrop.height, dragndrop.angle);
                    var center_x = (x_corners[0] + x_corners[1] + x_corners[2] + x_corners[3]) / 4;
                    var center_y = (y_corners[0] + y_corners[1] + y_corners[2] + y_corners[3]) / 4;

                    var min_x_corner = x_corners[0];
                    var max_x_corner = x_corners[3];

                    var min_y_corner = y_corners[0];
                    var max_y_corner = y_corners[3];
                    if (dragndrop.grid_active && dragndrop.moveable) {
                        var dif_min_x_corner = ((min_x_corner - dragndrop.contain_x) / dragndrop.distance - Math.floor((min_x_corner - dragndrop.contain_x) / dragndrop.distance)) * dragndrop.distance;
                        var dif_max_x_corner = ((max_x_corner - dragndrop.contain_x) / dragndrop.distance - Math.floor((max_x_corner - dragndrop.contain_x) / dragndrop.distance)) * dragndrop.distance
                        if (dif_min_x_corner <= dif_max_x_corner) {
                            new_top_left_x -= dif_min_x_corner;
                            dragndrop.drawVerticalLine = 'front';
                        }
                        else {
                            new_top_left_x -= dif_max_x_corner;
                            dragndrop.drawVerticalLine = 'back';
                        }
                        var dif_min_y_corner = ((min_y_corner - dragndrop.contain_y) / dragndrop.distance - Math.floor((min_y_corner - dragndrop.contain_y) / dragndrop.distance)) * dragndrop.distance;
                        var dif_max_y_corner = ((max_y_corner - dragndrop.contain_y) / dragndrop.distance - Math.floor((max_y_corner - dragndrop.contain_y) / dragndrop.distance)) * dragndrop.distance;
                        if (dif_min_y_corner <= dif_max_y_corner) {
                            new_top_left_y -= dif_min_y_corner;
                            dragndrop.drawHorizontalLine = 'top';
                        }
                        else {
                            new_top_left_y -= dif_max_y_corner;
                            dragndrop.drawHorizontalLine = 'bottom';
                        }

                    }
                    else {
                        dragndrop.drawVerticalLine = '';
                        dragndrop.drawHorizontalLine = '';
                    }
                    // code to prevent dragndrop from going out of bounds
                    if (min_x_corner < dragndrop.contain_x) {
                        // prevent dragndrop from going out of bounds on the left
                        var offset = center_x - min_x_corner - dragndrop.width / 2;
                        new_top_left_x = offset + dragndrop.contain_x;
                    }
                    if (max_x_corner > dragndrop.contain_x + dragndrop.contain_width) {
                        // prevent dragndrop from going out of bounds on the right
                        var offset = max_x_corner - center_x - dragndrop.width / 2;
                        new_top_left_x = dragndrop.contain_x - offset + dragndrop.contain_width - dragndrop.width;
                    }
                    if (min_y_corner < dragndrop.contain_y) {
                        // prevent dragndrop from going out of bounds on the top
                        var offset = center_y - min_y_corner - dragndrop.height / 2;
                        new_top_left_y = offset + dragndrop.contain_y;
                    }
                    if (max_y_corner > dragndrop.contain_y + dragndrop.contain_height) {
                        // prevent dragndrop from going out of bounds on the bottom
                        var offset = max_y_corner - center_y - dragndrop.height / 2;
                        new_top_left_y = dragndrop.contain_y - offset + dragndrop.contain_height - dragndrop.height;
                    }

                    dragndrop.x = new_top_left_x; //update dragndrop x position
                    dragndrop.y = new_top_left_y; //update dragndrop y position
                    dragndrop.center_x = dragndrop.x + dragndrop.width / 2; //update dragndrop center x position
                    dragndrop.center_y = dragndrop.y + dragndrop.height / 2; //update dragndrop center y position
                    dragndrop.changed = true; //indicates change so that the dragndrops will be added to the undo stack
                }
                triggerRepaint();
            }
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.active) {
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
                    //changes the cursor to the resize cursors
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
        this.image.clear();
        this.text.clear();
        this.dragndrops = [];
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
    }
}
canvasuijs.addType('DragNDrop', UIDragNDrop);