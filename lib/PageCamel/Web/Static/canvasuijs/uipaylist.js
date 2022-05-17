class UIPayList {
    constructor(canvass) {
        this.arrowbutton = new UIArrowButton();
        this.paylists = [];
        this.listitem = new UIListItem();
    }
    add(options) {
        options.scrollposition = 0;
        options.list = [];
        options.max_paylist_items = Math.round((options.height - (options.pagescrollbuttonheight + 5)) / options.elementOptions.height - 0.49);
        options.scrollbarsize = options.height - options.pagescrollbuttonheight - 2 * options.scrollbarwidth - options.border_width;
        options.scrollbar_y = options.scrollbarwidth + options.border_width / 2;
        options.mousedown_scrollbar_y = null;
        options.setList = (params) => {
            options.list = params;
            if (options.list.length > options.max_paylist_items) {
                //autoscrolling when scrolled to bottom of list
                options.scrollposition = options.list.length - options.max_paylist_items;
            }
            else if (options.list.length < options.max_paylist_items) {
                options.scrollposition = 0;

            }
            if (options.list.length <= options.selectedID) {
                options.selectedID = null;
            }
            this.update()
            return;
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



        options.scrollup = () => {
            if (options.scrollposition > 0) {
                options.scrollposition -= 1;
                this.update();
            }
            return;
        }
        options.scrolldown = () => {
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
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.scrollup, hover_border: options.hover_border
        });
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y + options.height - options.scrollbarwidth - options.pagescrollbuttonheight, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'down',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.scrolldown, hover_border: options.hover_border
        });
        //bottom Page Scroll Button
        this.arrowbutton.add({
            x: options.x, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'up',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.previousPage, hover_border: options.hover_border
        });
        this.arrowbutton.add({
            x: options.x + options.width / 2 + 2, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'down',
            background: options.background, foreground: options.foreground, border: options.border, border_width: options.border_width, hover_border: '#000000',
            callback: options.nextPage, hover_border: options.hover_border
        });
        this.paylists.push(options);


        return options;
    }

    update() {
        this.listitem.clear()
        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            var x = paylist.x;
            var font_size = paylist.elementOptions.font_size;
            var selectedBackground = paylist.elementOptions.selectedBackground;
            var foreground = paylist.foreground;
            var width = paylist.width - paylist.scrollbarwidth;
            var max_scrollbarheight = paylist.height - paylist.pagescrollbuttonheight - 2 * paylist.scrollbarwidth - paylist.border_width;
            paylist.scrollbarsize = this.getScrollbarSize(paylist.max_paylist_items, paylist.list.length) * max_scrollbarheight;
            paylist.scrollbar_y = (max_scrollbarheight - paylist.scrollbarsize)
                * (paylist.scrollposition / (paylist.list.length - paylist.max_paylist_items)) + paylist.scrollbarwidth + paylist.border_width / 2; // calculate scrollbar y position
            if (!paylist.scrollbar_y) {
                paylist.scrollbar_y = paylist.scrollbarwidth + paylist.border_width / 2
            }
            for (var j in paylist.list) {
                var index = j - paylist.scrollposition;
                if (index < paylist.max_paylist_items && index >= 0) {
                    var item = paylist.list[j];
                    var y = paylist.y + paylist.elementOptions.height * index;
                    this.listitem.add({
                        ...{
                            x: x, y: y, width: width, height: paylist.elementOptions.height, font_size: font_size, selected: paylist.selectedID, border_width: paylist.border_width,
                            selectedBackground: selectedBackground, foreground: foreground, callback: paylist.setSelected, id: j
                        }, ...item
                    });
                }
            }
        }
        triggerRepaint();
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
        for (var i in this.paylists) {
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
                triggerRepaint();
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

}