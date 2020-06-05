class CanvasTouchItemlist {
    constructor(canvas, scrollCallback, selectCallback) {
        this.canvas = canvas;
        this.scrollCallback = scrollCallback;
        this.selectCallback = selectCallback;
        
        this.ctx = document.getElementById(this.canvas).getContext('2d');
        
        this.buttonlist = [];
        
        this.checkButtonClick = this.checkButtonClick.bind(this);
        this.canvasMouseDown = this.canvasMouseDown.bind(this);
        this.canvasMouseUp = this.canvasMouseUp.bind(this);
        this.canvasMouseMove = this.canvasMouseMove.bind(this);
        
        $('#' + this.canvas).on('click', this.checkButtonClick);
        
        $(document).on('mousedown', this.canvasMouseDown);
        $(document).on('mousemove', this.canvasMouseMove);
        $(document).on('mouseup', this.canvasMouseUp);
        
        this.mousedown = 0;
        this.mousey = 0;
        this.itemlistcount = 0;
        this.itemoffset = 0;
        this.itemsizepixels = 0;
    }
    
    canvasMouseDown(e) {
        if(this.buttonlist.length == 0) {
            return;
        }

        var canvas = $('#' + this.canvas);
        var x = Math.floor((e.pageX-canvas.offset().left));
        var y = Math.floor((e.pageY-canvas.offset().top));
        
        for(var i = 0; i < this.buttonlist.length; i++) {
            if(x >= this.buttonlist[i].startx &&
               x <= this.buttonlist[i].endx &&
               y >= this.buttonlist[i].starty &&
               y <= this.buttonlist[i].endy &&
               this.buttonlist[i].scrollListEvent === 'drag') {

                this.mousedown = 1;
            }
        }

        return;
    }
    
    canvasMouseUp(e) {
        this.mousedown = 0;
        
        return;
    }
    
    canvasMouseMove(e) {
        if(!this.mousedown) {
            return;
        }

        var newmousey = e.pageY-$("#poscanvas").offset().top;
        var diff = this.mousey - newmousey;
        
        if(diff > this.itemsizepixels && this.itemoffset > 0) {
            this.mousey = this.mousey - this.itemsizepixels;
            this.itemoffset = this.itemoffset - 1;
            this.scrollCallback(this.itemoffset);
        } else if(diff < (-1 * this.itemsizepixels) /*&& invoicelistoffset < (invoicelist.length - itemlistcount)*/) {
            this.mousey = this.mousey + this.itemsizepixels;
            this.itemoffset = this.itemoffset + 1;
            this.scrollCallback(this.itemoffset);
        }
        
        return;
    }


    clearButtons() {
        this.buttonlist.length = 0;
    }
    
    addScrollList(x, y, width, height, itemList, scrollOffset, selectedItem) {
        
        //var realheight = height;
        height = height - 50;

        this.ctx.fillStyle = '#FFFFFF';
        this.ctx.strokeStyle = '#000000';
        this.ctx.fillRect(x, y, width - 1, height - 1);
        this.ctx.strokeRect(x, y, width - 1, height - 1);
        
        var listCount = Math.floor((height - 10) / 24);
        if(scrollOffset == -1 || scrollOffset > (itemList.length - listCount)) {
            scrollOffset = itemList.length - listCount;
            if(scrollOffset < 0) {
                scrollOffset = 0;
            }
            this.scrollCallback(scrollOffset);
        }
        
        if(selectedItem != -1) {
            var selector = selectedItem - scrollOffset;
            var ystart = y + 1 + (selector * 24);
            var yend = ystart + 24;
            if(ystart > y && yend < (y + height)) {
                this.ctx.fillStyle = '#F8FC03';
                this.ctx.fillRect(x + 1, y + 1 + (selector * 24) , width - 25, 24);
            }
        }
               
        //   invoice list
        this.ctx.font="20px Courier";
        this.ctx.fillStyle = '#000000';
        var maxItemCount = listCount;
        if(itemList.length < maxItemCount) {
            maxItemCount = itemList.length;
        }
        for(var i = 0; i < maxItemCount; i++) {
            if(itemList[i + scrollOffset].match(/^\^#/)) {
                var textcolor = itemList[i + scrollOffset].substr(1, 7);
                this.ctx.fillStyle = textcolor;
                //this.ctx.fillStyle = '#00FF00';
                var tempitem = itemList[i + scrollOffset].substring(8);
                this.ctx.fillText(tempitem, x + 5, y + 20 + (i * 24));
            } else {
                this.ctx.fillStyle = '#000000';
                this.ctx.fillText(itemList[i + scrollOffset], x + 5, y + 20 + (i * 24));
            }
            
            this.buttonlist.push({
                startx: x + 1,
                starty: y + 1 + (i * 24),
                endx: x + 1 + width - 24,
                endy: y + 1 + (i * 24) + 23,
                selectItem: i + scrollOffset,
                scrollListEvent: 'select'
            });
            
        }

        // Scrollbar
        this.ctx.strokeStyle = '#000000';
        
        this.ctx.fillStyle = '#A0A0A0';
        this.ctx.fillRect(x + width - 23, y + 23, 20, height - 46);
        
        this.ctx.fillStyle = '#000000';
        this.ctx.font="20px Courier";
        

        // Scrollbar up arrow
        this.ctx.strokeRect(x + width - 23, y + 3, 20, 20);
        drawArrow(this.ctx, x + width - 22, y + 4, 18, 18, 'up');
        if(scrollOffset > 0) {
            this.buttonlist.push({
                startx: x + width - 23,
                starty: y + 3,
                endx: x + width - 23 + 20,
                endy: y + 3 + 20,
                scrollListEvent: 'scroll',
                scrollTo: scrollOffset - 1
            });
        }
        
            // Scrollbar Down Arrow
        this.ctx.strokeRect(x + width - 23, y + height - 23, 20, 20);
        drawArrow(this.ctx, x + width - 22, y + height - 22, 18, 18, 'down');
        if(scrollOffset < (itemList.length - listCount)) {
            this.buttonlist.push({
                startx: x + width - 23,
                starty: y + height - 23,
                endx: x + width - 23 + 20,
                endy: y + height - 23 + 20,
                scrollListEvent: 'scroll',
                scrollTo: scrollOffset + 1
            });
        }
        
        
            // bar
        var totallen = (y + height - 23) - (y + 23) - 4;
        var barlen = totallen;
        var barstart = y + 25;
        if(itemList.length > listCount) {
            var lenpercent = listCount / itemList.length;
            barlen = Math.floor(barlen * lenpercent);
            
            var startpercent = invoicelistoffset / invoicelist.length;
            barstart = barstart + Math.floor(totallen * startpercent);
        }
        this.ctx.fillStyle = '#000000';
        this.ctx.fillRect(x + width - 23, barstart, 20, barlen);

        if(barstart > y + 25) {
            var scrolltmp = scrollOffset - 10;
            if(scrolltmp < 0) {
                scrolltmp = 0;
            }
            this.buttonlist.push({
                startx: x + width - 23,
                starty: y + 25,
                endx: x + width - 23 + 20,
                endy: barstart,
                scrollListEvent: 'scroll',
                scrollTo: scrolltmp
            });
        }
        
        this.itemoffset = scrollOffset;
        this.itemsizepixels = (barlen / totallen) * listCount;

        if((barstart + barlen) < (y + 25 + totallen)) {
            var scrolltmp = scrollOffset + 10;
            if(scrolltmp > (itemList.length - listCount)) {
                scrolltmp = itemList.length - listCount;
            }
            this.buttonlist.push({
                startx: x + width - 23,
                starty: barstart + barlen,
                endx: x + width - 23 + 20,
                endy: y + 25 + totallen,
                scrollListEvent: 'scroll',
                scrollTo: scrolltmp
            });
        }

        this.buttonlist.push({
            startx: x + width - 23,
            starty: barstart,
            endx: x + width - 23 + 20,
            endy: barstart + barlen,
            scrollListEvent: 'drag',
        });
        
        // Touchbar Up Arrow
        this.ctx.fillStyle = '#FFFFFF';
        this.ctx.strokeStyle = '#000000';

        var xstart = x;
        var ystart = y + height + 5;
        var bwidth = (width / 2) - 5;
        var bheight = 40;
        this.ctx.fillRect(xstart, ystart, bwidth, bheight);
        this.ctx.strokeRect(xstart, ystart, bwidth, bheight);
        
        this.ctx.fillStyle = '#000000';
        drawArrow(this.ctx, xstart + (bwidth / 2) - 30, ystart + 5, 60, 30, 'up');
        if(scrollOffset > 0) {
            var newscrollto = scrollOffset - 10;
            if(newscrollto < 0) {
                newscrollto = 0;
            }
            this.buttonlist.push({
                startx: xstart,
                starty: ystart,
                endx: xstart + bwidth - 1,
                endy: ystart + bheight - 1,
                scrollListEvent: 'scroll',
                scrollTo: newscrollto
            });
        }
        
        // Touchbar Down Arrow
        this.ctx.fillStyle = '#FFFFFF';
        this.ctx.strokeStyle = '#000000';
        xstart = x + bwidth + 10;
        
        this.ctx.fillRect(xstart, ystart, bwidth, bheight);
        this.ctx.strokeRect(xstart, ystart, bwidth, bheight);
        
        this.ctx.fillStyle = '#000000';
        drawArrow(this.ctx, xstart + (bwidth / 2) - 30, ystart + 5, 60, 30, 'down');
        if(scrollOffset < (itemList.length - listCount)) {
            var newscrollto = scrollOffset + 10;
            if(newscrollto >= itemList.length) {
                newscrollto = itemList.length - 1;
            }
            this.buttonlist.push({
                startx: xstart,
                starty: ystart,
                endx: xstart + bwidth - 1,
                endy: ystart + bheight - 1,
                scrollListEvent: 'scroll',
                scrollTo: newscrollto
            });
        }
        
        return listCount;
    }
    
    checkButtonClick(e) {
        if(this.buttonlist.length == 0) {
            return;
        }

        var canvas = $('#' + this.canvas);
        var x = Math.floor((e.pageX-canvas.offset().left));
        var y = Math.floor((e.pageY-canvas.offset().top));
        
        for(var i = 0; i < this.buttonlist.length; i++) {
            if(x >= this.buttonlist[i].startx &&
               x <= this.buttonlist[i].endx &&
               y >= this.buttonlist[i].starty &&
               y <= this.buttonlist[i].endy
               ) {

                if(this.buttonlist[i].scrollListEvent === 'select') {
                    this.selectCallback(this.buttonlist[i].selectItem);
                } else if(this.buttonlist[i].scrollListEvent === 'scroll') {
                    this.scrollCallback(this.buttonlist[i].scrollTo);
                }
            }
        }
        
        return;
    }

}

