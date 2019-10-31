class CanvasButtons {
    constructor(canvas) {
        this.canvas = canvas;
        
        this.ctx = document.getElementById(this.canvas).getContext('2d');
        this.buttonlist = new Array();
        
        this.clearButtons = this.clearButtons.bind(this);
        this.addButton = this.addButton.bind(this);
        this.checkButtonClick = this.checkButtonClick.bind(this);
        
        $('#' + this.canvas).on('click', this.checkButtonClick);
    }
    
    clearButtons() {
        this.buttonlist.length = 0;
    }
    
    addButton(x, y, width, height, buttontext, textcolor, buttoncolor, callback, callbackData, roundCorner) {
        if(typeof(roundCorner) === 'undefined') {
            roundCorner = 0;
        }

        this.ctx.strokeStyle = '#000000';
        this.ctx.fillStyle = buttoncolor;
        
        if(!roundCorner) {
            this.ctx.fillRect(x, y, width, height);
            this.ctx.strokeRect(x, y, width, height);
        } else {
            roundRect(this.ctx, x, y, width, height, roundCorner);
        }
        
        this.ctx.fillStyle = textcolor;
        this.ctx.strokeStyle = textcolor;
        if(!buttontext.includes("\n")) {
            this.ctx.fillText(buttontext, x + 8, y + (height / 2));
        } else {
            var blines = buttontext.split("\n");
            var yoffs = y + ((height / 2) - (9 * (blines.length - 1)));
            var i;
            for(i = 0; i < blines.length; i++) {
                blines[i].replace("\n", '');
                this.ctx.fillText(blines[i], x + 8, yoffs);
                yoffs = yoffs + 18;
            }
        }
        
        var thisbutton = {
            startx: x,
            starty: y,
            endx: x+width,
            endy: y+height,
            displaytext: buttontext,
            callback: callback,
            callbackData: callbackData
        };
        
        this.buttonlist.push(thisbutton);
        return;
    }
    
    checkButtonClick(e) {
        var canvas = $('#' + this.canvas);
        var x = Math.floor((e.pageX-canvas.offset().left));
        var y = Math.floor((e.pageY-canvas.offset().top));
        
        for(var i = 0; i < this.buttonlist.length; i++) {
            if(x >= this.buttonlist[i].startx &&
               x <= this.buttonlist[i].endx &&
               y >= this.buttonlist[i].starty &&
               y <= this.buttonlist[i].endy
               ) {
                
                this.buttonlist[i].callback(this.buttonlist[i].callbackData);
            }
        }
        
        return;
    }

}

