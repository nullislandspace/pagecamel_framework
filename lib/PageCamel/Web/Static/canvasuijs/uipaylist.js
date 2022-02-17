class UIPayList {

    constructor() {
        this.arrowbutton = new UIArrowButton();
        this.paylists = [];
    }
    add(options) {
        options.scrollbarsize = 1;
        options.previousPage = (params) => {
            console.log('previous Page');
            //options.pagePosition -= 1;
            //this.createList();
        }
        options.nextPage = (params) => {
            console.log('next Page');
            //options.pagePosition += 1;
            //this.createList();
        }
        options.setScrollbarSize = (params) => {

        }
        options.scrollup = (params) => {
            console.log('scrollup');
        }
        options.scrolldown = (params) => {
            console.log('scrolldown');
        }

        //right scroll bar
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'up',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
            callback: options.scrollup
        });
        this.arrowbutton.add({
            x: options.x + options.width - options.scrollbarwidth, y: options.y + options.height - options.scrollbarwidth - options.pagescrollbuttonheight, width: options.scrollbarwidth, height: options.scrollbarwidth, direction: 'down',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 1, hover_border: '#000000',
            callback: options.scrolldown
        });
        //bottom Page Scroll Button
        this.arrowbutton.add({
            x: options.x, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'up',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
            callback: options.previousPage
        });
        this.arrowbutton.add({
            x: options.x + options.width / 2 + 2, y: options.y + options.height - options.pagescrollbuttonheight + 5, width: options.width / 2 - 2, height: options.pagescrollbuttonheight, direction: 'down',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3, hover_border: '#000000',
            callback: options.nextPage
        });
        this.paylists.push(options);


        return options;
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
                paylist.scrollbarwidth + paylist.border_width /2, paylist.height - paylist.pagescrollbuttonheight - paylist.scrollbarwidth);


        }

        this.arrowbutton.render(ctx);
    }
    onClick(x, y) {
        this.arrowbutton.onClick(x, y);
        return;
    }
    onHover(x, y) {
        this.arrowbutton.onHover(x, y);
        return;
    }
    onMouseDown(x, y) {
        this.arrowbutton.onMouseDown(x, y);
        return;
    }
    onMouseUp(x, y) {
        this.arrowbutton.onMouseUp(x, y);
        return;
    }
    find(name) {
        return;
    }

}