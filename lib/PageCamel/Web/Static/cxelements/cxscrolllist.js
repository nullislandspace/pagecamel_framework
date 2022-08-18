class CXScrollList extends CXFrame {
    constructor(ctx, x, y, width, height, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.radius = 10;
        this._render_list = [];
        this._scroll_list_items = [];
        this._item_height = 0.05;

        this.scroll_bar = new CXScrollBar(ctx, 0.95, 0.0, 0.05, 1.0, true, false);
        this.scroll_bar.scrollbar.radius = 5;
        this.scroll_bar.radius = 5;

        this._selected_index = null;

        this._setRows();

        this.border_width = 2;
        this._elements.push(this.scroll_bar);
    }
    _setRows() {
        this.scroll_bar.rows = this._scroll_list_items.length;
        this.scroll_bar.rows_per_page = 1 / this._item_height;
    }
    _checkMouseMove(x, y) {
        if (this._mouse_down) {
            return true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this._mouse_over = true;
            return true;
        } else if (this._mouse_over) {
            this._mouse_over = false;
            return true;
        }
        return false;
    }
    _draw() {
        this._ctx.clearRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        this._ctx.fillStyle = "white";
        this._ctx.fillRect(this.xpixel, this.ypixel, this.widthpixel, this.heightpixel);
        super._draw(); // draws the frame of the parent class

        /* calculates new positions to not overlap with the border */
        var x = this.xpixel + this._border_width;
        var y = this.ypixel + this._border_width;
        var w = this.widthpixel - 2 * this._border_width;
        var h = this.heightpixel - 2 * this._border_width;
        this._elements.forEach(element => {
            element.draw(x, y, w, h);
        }
        );
        // gets the current row of the scroll bar
        var scroll_position = this.scroll_bar.scroll_position;
        // get the list of items to be displayed
        this._render_list = this._scroll_list_items.slice(scroll_position, scroll_position + this.scroll_bar.rows_per_page);
        // draw the items
        for (let i = 0; i < this._render_list.length; i++) {
            this._render_list[i].ypos = i * this._item_height;
            this._render_list[i].draw(x, y, w, h);

        }
    }
    handleEvent(event) {
        var redraw = false;
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    redraw = true;
                }
            }
        });
        var index = null;
        for (let i = 0; i < this._render_list.length; i++) {
            if (this._render_list[i].checkEvent(event)) {
                this._render_list[i].handleEvent(event);
                if (this._render_list[i].has_changed) {
                    redraw = true;
                    index = i;
                    break;
                }
            }
        }
        if(index !== null){
            index += this.scroll_bar.scroll_position;
            this._selected_index = index;
            //goes through all the items and sets the selected property to false
            for(let i = 0; i < this._scroll_list_items.length; i++){
                if(i !== index){
                    this._scroll_list_items[i].selected = false; // deselect item
                }
            }
        }
        if (redraw && this._redraw) {
            this._draw();
        }
    }
    /**
     * @param {Array} list - Array of strings in the format [[item1, item2, item3], [item4, item5, item6]]
     * @description Sets the list of items to be displayed in the scroll list
     */
    set list(list) {
        this._scroll_list_items = []
        for (let i = 0; i < list.length; i++) {
            var list_item = new CXScrollListItem(this._ctx, 0.0, this._item_height * i, 0.95, this._item_height, true, false);
            //list_item.box_color = "transparent";
            list_item.listitem = list[i];
            list_item.radius = 5;
            list_item.border_width = 0;
            this._scroll_list_items.push(list_item);
            this._setRows();
        }
        if (this._redraw) {
            this._draw();
        }
    }
}