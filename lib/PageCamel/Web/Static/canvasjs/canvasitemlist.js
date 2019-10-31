class CanvasItemlist {
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
            if(selector => 0 && selector < listCount) {
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
            this.ctx.fillText(itemList[i + scrollOffset], x + 5, y + 20 + (i * 24));
            
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
        this.ctx.fillStyle = '#000000';
        this.ctx.font="20px Courier";
        
            // Note to self: available arrows: ⮜ ⮞ ⮝ ⮟
            // Upper arrow
        this.ctx.strokeRect(x + width - 23, y + 3, 20, 20);
        this.ctx.fillText('⮝', x + width - 22, y + 22);
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
        
            // Lower Arrow
        this.ctx.strokeRect(x + width - 23, y + height - 23, 20, 20);
        this.ctx.fillText('⮟', x + width - 22, y + height - 8);
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
                    this.selectCallback(this.buttonlist[i].selectCallback);
                } else if(this.buttonlist[i].scrollListEvent === 'scroll') {
                    this.scrollCallback(this.buttonlist[i].scrollTo);
                }
            }
        }
        
        return;
    }

}

