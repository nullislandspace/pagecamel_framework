class UIDragNDrop {
    constructor(canvas) {
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
            dragndrop.callback(dragndrop.callbackData, dragndrop);
            triggerRepaint();
        }
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