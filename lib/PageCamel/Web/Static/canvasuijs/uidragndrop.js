class UIDragNDrop {
    constructor(canvas) {
        this.textbox = new UITextBox();
        this.circle = new UICircle();
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
        options.resizedirection = '';
        options.mouse_down_action = '';
        options.moveable = false;
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
        this.textbox.render(ctx);
        for (var i in this.dragndrops) {
            var dragndrop = this.dragndrops[i];
            if (dragndrop.editable == true && dragndrop.selected == true) {
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
            }
        }

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
            if (dragndrop.resizeable && dragndrop.editable && dragndrop.selected) {
                this.mouse_down = true;
                this.array_move(this.dragndrops, i, this.dragndrops.length - 1);
                this.textbox.textboxes = this.dragndrops;
                this.mouse_down_x = x - startx;
                this.mouse_down_y = y - starty;
                dragndrop.mouse_down_action = dragndrop.resizedirection;
                console.log(dragndrop.mouse_down_action);
                return;
            }
            else {
                dragndrop.mouse_down_action = '';
            }
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                dragndrop.selected = true;
                var g_id = dragndrop.group_id;
                for (var j = this.dragndrops.length - 1; j >= 0; j--) {
                    var s_dragndrop = this.dragndrops[j];
                    if (s_dragndrop.group_id == g_id && j != i) {
                        s_dragndrop.selected = false;
                    }
                }
                this.mouse_down = true;
                this.array_move(this.dragndrops, i, this.dragndrops.length - 1);
                this.textbox.textboxes = this.dragndrops;
                this.mouse_down_x = x - startx;
                this.mouse_down_y = y - starty;
                triggerRepaint();
                return;
            }
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var s_dragndrop = this.dragndrops[i];
            s_dragndrop.selected = false;
        }
        triggerRepaint();
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
    onMouseMove(x, y) {
        if (this.mouse_down) {
            var dragndrop = this.dragndrops[this.dragndrops.length - 1];
            //when mouse is down on drag and drop item
            if (dragndrop.mouse_down_action != '' && dragndrop.editable == true && dragndrop.selected) {
                //when button (resize) is pressed
                $(this.canvas).css('cursor', dragndrop.mouse_down_action);
                var new_height = dragndrop.height;
                var new_width = dragndrop.width;
                var new_x = dragndrop.x;
                var new_y = dragndrop.y;
                if (dragndrop.mouse_down_action == 's-resize' || dragndrop.mouse_down_action == 'se-resize' || dragndrop.mouse_down_action == 'sw-resize') {
                    new_height = y - dragndrop.y;
                    if (new_height <= this.box_size + 2) {
                        new_height = this.box_size + 2;
                    }
                }
                if (dragndrop.mouse_down_action == 'e-resize' || dragndrop.mouse_down_action == 'ne-resize' || dragndrop.mouse_down_action == 'se-resize') {
                    new_width = x - dragndrop.x;
                    if (new_width <= this.box_size + 2) {
                        new_width = this.box_size + 2;
                    }
                }
                if (dragndrop.mouse_down_action == 'n-resize' || dragndrop.mouse_down_action == 'ne-resize' || dragndrop.mouse_down_action == 'nw-resize') {
                    new_y = y;
                    new_height = dragndrop.height + (dragndrop.y - y);
                    if (new_height <= this.box_size + 2) {
                        new_y = new_y - (this.box_size + 2 - new_height);
                        new_height = this.box_size + 2;
                    }
                }
                if (dragndrop.mouse_down_action == 'w-resize' || dragndrop.mouse_down_action == 'nw-resize' || dragndrop.mouse_down_action == 'sw-resize') {
                    new_x = x;
                    new_width = dragndrop.width + (dragndrop.x - x);
                    if (new_width <= this.box_size + 2) {
                        new_x = new_x - (this.box_size + 2 - new_width);
                        new_width = this.box_size + 2;
                    }
                }
                if (new_x < dragndrop.contain_x) {
                    new_x = dragndrop.contain_x;
                    new_width = dragndrop.width + (dragndrop.x - dragndrop.contain_x);
                }
                if (new_y < dragndrop.contain_y) {
                    new_y = dragndrop.contain_y;
                    new_height = dragndrop.height + (dragndrop.y - dragndrop.contain_y);;
                }
                if (new_x + new_width > dragndrop.contain_x + dragndrop.contain_width) {
                    new_width = dragndrop.contain_x + dragndrop.contain_width - new_x;
                }
                if (new_y + new_height > dragndrop.contain_y + dragndrop.contain_height) {
                    new_height = dragndrop.contain_y + dragndrop.contain_height - new_y;
                }
                dragndrop.width = new_width;
                dragndrop.height = new_height;
                dragndrop.y = new_y;
                dragndrop.x = new_x;
                //console.log(dragndrop.mouse_down_action);
            }
            else {
                $(this.canvas).css('cursor', 'move');
                var new_top_left_x = x - this.mouse_down_x;
                var new_top_left_y = y - this.mouse_down_y;

                var new_bottom_right_x = new_top_left_x + dragndrop.width;
                var new_bottom_right_y = new_top_left_y + dragndrop.height;
                if (new_top_left_x < dragndrop.contain_x) {
                    new_top_left_x = dragndrop.contain_x;
                }
                if (new_top_left_y < dragndrop.contain_y) {
                    new_top_left_y = dragndrop.contain_y;
                }
                if (new_bottom_right_x > dragndrop.contain_x + dragndrop.contain_width) {
                    new_top_left_x = dragndrop.contain_x + dragndrop.contain_width - dragndrop.width;
                }
                if (new_bottom_right_y > dragndrop.contain_y + dragndrop.contain_height) {
                    new_top_left_y = dragndrop.contain_y + dragndrop.contain_height - dragndrop.height;
                }
                dragndrop.x = new_top_left_x;
                dragndrop.y = new_top_left_y;

            }
            dragndrop.callback(dragndrop.callbackData, dragndrop);
            triggerRepaint();
        }
        for (var i = this.dragndrops.length - 1; i >= 0; i--) {
            var dragndrop = this.dragndrops[i];
            var startx = dragndrop.x;
            var starty = dragndrop.y;
            var endx = startx + dragndrop.width;
            var endy = starty + dragndrop.height;
            dragndrop.resizeable = false;
            dragndrop.moveable = false;
            if (x >= startx && x <= endx && y >= starty && y <= endy && dragndrop.mouse_down_action == '') {
                $(this.canvas).css('cursor', 'move');
                dragndrop.moveable = true;
            }
            if (dragndrop.editable && dragndrop.selected) {
                //dragndrop.editable allows resizing
                this.setCursorAtLocation(x, y, dragndrop.x - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size, "nw-resize", dragndrop);
                this.setCursorAtLocation(x, y, dragndrop.x - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size, "sw-resize", dragndrop);
                this.setCursorAtLocation(x, y, dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size, "ne-resize", dragndrop);
                this.setCursorAtLocation(x, y, dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size, "se-resize", dragndrop);
                if (dragndrop.width > 2 * this.box_size) {
                    this.setCursorAtLocation(x, y, dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y - this.box_size_half, this.box_size, this.box_size, "n-resize", dragndrop);
                    this.setCursorAtLocation(x, y, dragndrop.x + dragndrop.width / 2 - this.box_size_half, dragndrop.y + dragndrop.height - this.box_size_half, this.box_size, this.box_size, "s-resize", dragndrop);
                }
                if (dragndrop.height > 2 * this.box_size) {
                    this.setCursorAtLocation(x, y, dragndrop.x - this.box_size_half, dragndrop.y + dragndrop.height / 2 - this.box_size_half, this.box_size, this.box_size, "w-resize", dragndrop);
                    this.setCursorAtLocation(x, y, dragndrop.x + dragndrop.width - this.box_size_half, dragndrop.y + dragndrop.height / 2 - this.box_size_half, this.box_size, this.box_size, "e-resize", dragndrop);
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
        this.dragndrops = [];
        this.mouse_down = false;
        this.mouse_down_x = null;
        this.mouse_down_y = null;
    }
}