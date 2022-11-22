class UIScrollList {
    constructor(canvas) {
        this.scrolllists = [];
    }
    add(options) {
        options.listitem = new UIListItem();
        options.arrowbutton = new UIArrowButton();
        options.scrollposition = 0;
        options.list = [];
        options.max_scrolllist_items = Math.round((options.height - (options.pagescrollbuttonheight + 5)) / options.elementOptions.height - 0.49);
        options.scrollbarsize = options.height - options.pagescrollbuttonheight - 2 * options.scrollbarwidth - options.border_width;
        options.scrollbar_y = options.scrollbarwidth + options.border_width / 2;
        options.mousedown_scrollbar_y = null;
        options.setList = (params) => {
            if (params !== undefined) {
                options.list = params;
                if (options.list.length > options.max_scrolllist_items) {
                    //autoscrolling when scrolled to bottom of list
                    options.scrollposition = options.list.length - options.max_scrolllist_items;
                }
                else if (options.list.length < options.max_scrolllist_items) {
                    options.scrollposition = 0;

                }
                if (options.list.length <= options.selectedID) {
                    options.selectedID = null;
                }
                this.update()
                return;
            }
            else {
                options.list = [];
            }
        }
        options.deleteSelected = () => {
            if (options.selectedID != null) {
                var index = options.getSelectedItemIndex();
                options.list.splice(index, 1);
                options.selectedID = null;
                options.setScrollPosition(options.scrollposition - 1);
                this.update();
            }
        }
        options.getList = () => {
            return options.list;
        }
        options.previousPage = () => {
            if (options.max_scrolllist_items < options.list.length) {
                if (options.scrollposition - options.max_scrolllist_items > 0) {
                    options.scrollposition -= options.max_scrolllist_items;
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
            if (options.max_scrolllist_items < options.list.length) {
                var nextitem = options.scrollposition + 2 * options.max_scrolllist_items;
                if (nextitem <= options.list.length) {
                    options.scrollposition += options.max_scrolllist_items;
                    this.update();
                }
                else {
                    options.scrollposition = options.list.length - options.max_scrolllist_items;
                    this.update();
                }
            }
            return;
        }



        options.scrollup = () => {
            if (options.scrollposition > 0) {
                options.scrollposition -= 1;
                this.update();
            }
            return;
        }
        options.scrolldown = () => {
            var nextitem = options.scrollposition + options.max_scrolllist_items + 1;
            if (nextitem <= options.list.length) {
                options.scrollposition += 1;
                this.update();
            }
            return;
        }
        options.setSelected = (id) => {
            options.selectedID = id;
            if (options.callback !== undefined && options.selectedID != null && options.selectedID !== undefined) {
                options.callback(id);
            }
            this.update();
            return;
        }
        options.getSelectedItemIndex = () => {
            return options.selectedID;
        }
        options.setScrollPosition = (position) => {
            if (options.max_scrolllist_items <= options.list.length) {

                if (position <= options.list.length - options.max_scrolllist_items && position > 0) {
                    options.scrollposition = position;
                    this.update();
                }
                else if (position + 1 > options.list.length - options.max_scrolllist_items) {
                    options.scrollposition = options.list.length - options.max_scrolllist_items;
                    this.update();
                }
                else if (position < 0) {
                    options.scrollposition = 0;
                    this.update();
                }
            }
        }


        //right scroll bar
        options.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'up',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.scrollup, hover_border: options.hover_border
        });
        options.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y + options.height - options.scrollbarwidth - options.pagescrollbuttonheight, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'down',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.scrolldown, hover_border: options.hover_border
        });
        //bottom Page Scroll Button
        options.arrowbutton.add({
            x: options.x, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'up',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.previousPage, hover_border: options.hover_border
        });
        options.arrowbutton.add({
            x: options.x + options.width / 2 + 2, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'down',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.nextPage, hover_border: options.hover_border
        });
        this.scrolllists.push(options);


        return options;
    }

    update() {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            scrolllist.listitem.clear();
            var x = scrolllist.x;
            var font_size = scrolllist.elementOptions.font_size;
            var selectedBackground = scrolllist.elementOptions.selectedBackground;
            var foreground = scrolllist.foreground;
            var width = scrolllist.width - scrolllist.scrollbarwidth;
            var max_scrollbarheight = scrolllist.height - scrolllist.pagescrollbuttonheight - 2 * scrolllist.scrollbarwidth - scrolllist.border_width;
            scrolllist.scrollbarsize = this.getScrollbarSize(scrolllist.max_scrolllist_items, scrolllist.list.length) * max_scrollbarheight;
            scrolllist.scrollbar_y = (max_scrollbarheight - scrolllist.scrollbarsize)
                * (scrolllist.scrollposition / (scrolllist.list.length - scrolllist.max_scrolllist_items)) + scrolllist.scrollbarwidth + scrolllist.border_width / 2; // calculate scrollbar y position
            if (!scrolllist.scrollbar_y) {
                scrolllist.scrollbar_y = scrolllist.scrollbarwidth + scrolllist.border_width / 2
            }
            for (var j in scrolllist.list) {
                var index = j - scrolllist.scrollposition;
                if (index < scrolllist.max_scrolllist_items && index >= 0) {
                    var item = scrolllist.list[j];

                    var y = scrolllist.y + scrolllist.elementOptions.height * index;
                    scrolllist.listitem.add({
                        ...{
                            x: x, y: y, width: width, height: scrolllist.elementOptions.height, font_size: font_size, selected: scrolllist.selectedID, border_width: scrolllist.border_width,
                            selectedBackground: selectedBackground, foreground: foreground, callback: scrolllist.setSelected, id: j
                        }, ...item
                    });
                }
            }
        }
        triggerRepaint();
    }
    getScrollbarSize(max_scrolllist_items, list_lenght) {
        var scrollbarsize = (1 / (list_lenght / max_scrolllist_items));
        if (scrollbarsize > 1) {
            scrollbarsize = 1;
        }
        return scrollbarsize;
    }
    render(ctx) {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            ctx.font = scrolllist.font_size +  'px ' + font_name;
            ctx.strokeStyle = scrolllist.border;
            ctx.lineWidth = scrolllist.border_width;
            var grd;
            if (scrolllist.grd_type == 'horizontal') {
                grd = ctx.createLinearGradient(scrolllist.x, scrolllist.y, scrolllist.x + scrolllist.width, scrolllist.y);
            }
            else if (scrolllist.grd_type == 'vertical') {
                grd = ctx.createLinearGradient(scrolllist.x, scrolllist.y, scrolllist.x, scrolllist.y + scrolllist.height - scrolllist.pagescrollbuttonheight);
            }
            if (scrolllist.grd_type) {
                var step_size = 1 / scrolllist.background.length;
                for (var j in scrolllist.background) {
                    grd.addColorStop(step_size * j, scrolllist.background[j]);
                    ctx.fillStyle = grd;
                }
            }
            if (scrolllist.background.length == 1) {
                ctx.fillStyle = scrolllist.background[0];
            }
            if (!scrolllist.border_radius) {
                ctx.fillRect(scrolllist.x, scrolllist.y, scrolllist.width, scrolllist.height - scrolllist.pagescrollbuttonheight);
                ctx.strokeRect(scrolllist.x, scrolllist.y, scrolllist.width, scrolllist.height - scrolllist.pagescrollbuttonheight);
            } else {
                roundRect(ctx, scrolllist.x, scrolllist.y, scrolllist.width, scrolllist.height - scrolllist.pagescrollbuttonheight, scrolllist.border_radius, scrolllist.border_width);
            }
            ctx.fillStyle = scrolllist.scrollbarbackground;
            ctx.fillRect(scrolllist.x + scrolllist.width - scrolllist.scrollbarwidth - scrolllist.border_width / 2, scrolllist.y + scrolllist.scrollbarwidth,
                scrolllist.scrollbarwidth + scrolllist.border_width / 2, scrolllist.height - scrolllist.pagescrollbuttonheight - scrolllist.scrollbarwidth);

            ctx.fillStyle = scrolllist.foreground;
            ctx.fillRect(scrolllist.x + scrolllist.width - scrolllist.scrollbarwidth - scrolllist.border_width / 2, scrolllist.y + scrolllist.scrollbar_y,
                scrolllist.scrollbarwidth + scrolllist.border_width / 2, scrolllist.scrollbarsize);
            scrolllist.listitem.render(ctx);
            scrolllist.arrowbutton.render(ctx);
        }


    }
    onClick(x, y) {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            scrolllist.listitem.onClick(x, y);
            scrolllist.arrowbutton.onClick(x, y);
        }

        return;
    }
    onMouseDown(x, y) {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            scrolllist.arrowbutton.onMouseDown(x, y);
            scrolllist.listitem.onMouseDown(x, y);
            var startx = scrolllist.x + scrolllist.width - scrolllist.scrollbarwidth - scrolllist.border_width / 2;
            var starty = scrolllist.y + scrolllist.scrollbarwidth;
            var endx = scrolllist.x + scrolllist.width + scrolllist.scrollbarwidth + scrolllist.border_width / 2;
            var endy = scrolllist.y + scrolllist.height - scrolllist.pagescrollbuttonheight - scrolllist.scrollbarwidth;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                var top_scrollbar = scrolllist.y + scrolllist.scrollbar_y;
                var below_scrollbar = top_scrollbar + scrolllist.scrollbarsize;
                starty = scrolllist.y + scrolllist.scrollbar_y;
                endy = starty + scrolllist.scrollbarsize;
                if (x >= startx && x <= endx && y >= starty && y <= endy) {
                    //Mouse Down on Scrollbar
                    scrolllist.mousedown_scrollbar_y = y - starty;
                }
                else if (y < top_scrollbar) {
                    //Mouse Down Above scrollbar
                    scrolllist.previousPage();
                }
                else if (y > below_scrollbar) {
                    //Mouse Down below scrollbar
                    scrolllist.nextPage();
                }
                return;
            }

        }
        return;
    }
    onMouseUp(x, y) {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            scrolllist.arrowbutton.onMouseUp(x, y);
            scrolllist.listitem.onMouseUp(x, y);
            scrolllist.mousedown_scrollbar_y = null;
        }
        return;
    }
    onMouseMove(x, y) {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            scrolllist.arrowbutton.onMouseMove(x, y);
            scrolllist.listitem.onMouseMove(x, y);
            if (scrolllist.mousedown_scrollbar_y != null) {
                var scroll_y = (y - scrolllist.mousedown_scrollbar_y) - (scrolllist.y + scrolllist.scrollbarwidth)//calculating scroll bar distance
                var max_scrollbarheight = scrolllist.height - scrolllist.pagescrollbuttonheight - 2 * scrolllist.scrollbarwidth - scrolllist.border_width;
                var empty_scrollbar_space = max_scrollbarheight - scrolllist.scrollbarsize;
                var scroll_position = Math.round(((scrolllist.list.length - scrolllist.max_scrolllist_items) / empty_scrollbar_space) * scroll_y);
                scrolllist.setScrollPosition(scroll_position);
                triggerRepaint();
            }

        }

        return;
    }
    find(name) {
        for (var i in this.scrolllists) {
            var scrolllist = this.scrolllists[i];
            if (scrolllist.name == name) {
                return scrolllist;
            }
        }
    }

}
canvasuijs.addType('ScrollList', UIScrollList);