class UIPayList {

    constructor() {
        this.arrowbutton = new UIArrowButton();
        this.paylists = [];
        this.listitem = new UIListItem();
    }
    add(options) {
        options.scrollbarsize = 1;
        options.scrollposition = 0;
        options.max_paylist_items = 0;
        options.scrollbarsize = options.height - options.pagescrollbuttonheight - 2 * options.scrollbarwidth - options.border_width;
        options.scrollbar_y = options.scrollbarwidth + options.border_width;
        options.setList = (params) => {
            options.list = params;
            this.update()
        }
        options.previousPage = (params) => {
            if (options.scrollposition - options.max_paylist_items > 0) {
                options.scrollposition -= options.max_paylist_items;
                this.update();
            }
            else {
                options.scrollposition = 0
                this.update();
            }

            console.log('previous Page');
        }
        options.nextPage = (params) => {
            var nextitem = options.scrollposition + 2 * options.max_paylist_items;
            if (nextitem <= options.list.length) {
                options.scrollposition += options.max_paylist_items;
                this.update();
            }
            else {
                options.scrollposition = options.list.length - options.max_paylist_items;
                this.update();
            }
            console.log('next Page');
        }



        options.scrollup = (params) => {
            if (options.scrollposition > 0) {
                options.scrollposition -= 1;
                this.update();
            }
            console.log('scrollup');
        }
        options.scrolldown = (params) => {
            var nextitem = options.scrollposition + options.max_paylist_items + 1;
            if (nextitem <= options.list.length) {
                options.scrollposition += 1;
                this.update();
            }
            console.log('scrolldown');
        }
        options.setSelected = (id) => {
            options.selectedID = id;
            this.update();
        }


        //right scroll bar
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'up',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.scrollup
        });
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y + options.height - options.scrollbarwidth - options.pagescrollbuttonheight, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'down',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.scrolldown
        });
        //bottom Page Scroll Button
        this.arrowbutton.add({
            x: options.x, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'up',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.previousPage
        });
        this.arrowbutton.add({
            x: options.x + options.width / 2 + 2, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'down',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: options.border_width, hover_border: '#000000',
            callback: options.nextPage
        });
        this.paylists.push(options);


        return options;
    }

    update() {
        this.listitem.clear()
        for (var i in this.paylists) {
            var paylist = this.paylists[i];
            var x = paylist.x;
            var height = paylist.elementOptions.height;
            var font_size = paylist.elementOptions.font_size;
            var selectedBackground = paylist.elementOptions.selectedBackground;
            var foreground = paylist.foreground;
            var width = paylist.width - paylist.scrollbarwidth;
            var name = paylist.name;
            paylist.max_paylist_items = Math.round((paylist.height - (paylist.pagescrollbuttonheight + 5)) / height - 0.49);
            var max_scrollbarheight = paylist.height - paylist.pagescrollbuttonheight - 2 * paylist.scrollbarwidth - paylist.border_width;
            paylist.scrollbarsize = this.getScrollbarSize(paylist.max_paylist_items, paylist.list.length) * max_scrollbarheight;
            paylist.scrollbar_y = (max_scrollbarheight - paylist.scrollbarsize)
             * (paylist.scrollposition / (paylist.list.length - paylist.max_paylist_items)) + paylist.scrollbarwidth + paylist.border_width / 2; // calculate scrollposition
            console.log(paylist.scrollbar_y);
            for (var j in paylist.list) {
                var index = j - paylist.scrollposition;
                if (index < paylist.max_paylist_items && index >= 0) {
                    var item = paylist.list[j];
                    var y = paylist.y + paylist.elementOptions.height * index;
                    this.listitem.add({
                        ...{
                            x: x, y: y, width: width, height: height, font_size: font_size, selected: paylist.selectedID, border_width: paylist.border_width,
                            selectedBackground: selectedBackground, foreground: foreground, name: name, callback: paylist.setSelected, id: j
                        }, ...item
                    });
                }
            }
        }
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
            ctx.fillRect(paylist.x + paylist.width - paylist.scrollbarwidth - paylist.border_width / 2, paylist.y,
                paylist.scrollbarwidth + paylist.border_width / 2, paylist.height - paylist.pagescrollbuttonheight - paylist.scrollbarwidth);

            ctx.fillStyle = paylist.foreground;
            ctx.fillRect(paylist.x + paylist.width - paylist.scrollbarwidth - paylist.border_width / 2, paylist.y +  paylist.scrollbar_y,
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
    onHover(x, y) {
        this.arrowbutton.onHover(x, y);
        this.listitem.onHover(x, y);
        return;
    }
    onMouseDown(x, y) {
        this.arrowbutton.onMouseDown(x, y);
        this.listitem.onMouseDown(x, y);
        return;
    }
    onMouseUp(x, y) {
        this.arrowbutton.onMouseUp(x, y);
        this.listitem.onMouseUp(x, y);
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