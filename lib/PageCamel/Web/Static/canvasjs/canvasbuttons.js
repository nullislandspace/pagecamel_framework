class CanvasButtons {
    constructor(canvas) {
        this.canvas = canvas;
        
        this.ctx = document.getElementById(this.canvas).getContext('2d');
        this.buttonlist = new Array();
        
        this.onClick = this.onClick.bind(this);
        this.addButtonGroup = this.addButtonGroup.bind(this);
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
    addButtonGroup(x, y, width, height, gap, buttontexts, keyvalues, textcolor, buttoncolor, callback, callbackData, roundCorner){
        let button_height = height / keyvalues.length - gap;
        let button_width = width / keyvalues[0].length - gap;
        for(let buttons_y = 0; buttons_y < keyvalues.length; buttons_y++) {
            for(let buttons_x = 0; buttons_x < keyvalues[0].length; buttons_x++){
                if (keyvalues[buttons_y][buttons_x] != null){
                    let position_x = x + (button_width + gap) * buttons_x;
                    let position_y = y - (button_height + gap) * buttons_y;
                    this.addButton(position_x, position_y, button_width, button_height, buttontexts[buttons_y][buttons_x], textcolor, buttoncolor,
                        callback, {key: callbackData['key'], value: keyvalues[buttons_y][buttons_x]},
                        roundCorner);
                }
            }
        }
    }

    addInvisibleButton(x, y, width, height, callback, callbackData) {
        var thisbutton = {
            startx: x,
            starty: y,
            endx: x+width,
            endy: y+height,
            displaytext: '',
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
    onClick() {

    }

}

