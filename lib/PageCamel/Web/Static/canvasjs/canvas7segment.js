class Canvas7Segment{
    constructor(canvas) {
        this.canvas = canvas;
        
        this.ctx = document.getElementById(this.canvas).getContext('2d');
        
        this.buttonlist = [];
        
        $('#' + this.canvas).on('click', this.checkButtonClick);
        
        this.segmentcoords = [
            [24, 25,  31, 16,  118, 16,  126, 25,  118, 34,  32, 34],
            [21, 28,  30, 36,  30, 94,  21, 103,  12, 95,  12, 37],
            [128, 28,  137, 36,  137, 94,  128, 103,  121, 95,  121, 37],
            [21, 110,  29, 117,  29, 175,  21, 184,  13, 175,  12, 118],
            [129, 109,  137, 117,  137, 176,  129, 184,  120, 176,  120, 118],
            [24, 187,  33, 178,  117, 178,  125, 187,  118, 196,  32, 196],
            [24, 106,  32, 97,  118, 97,  125, 105,  118, 114,  32, 114],
            [122, 195,  136, 181,  136, 195],
            [64, 55,  78, 55,  78, 68,  64, 68,  -1,-1,  64, 148,  78, 148,  78, 161,  64, 161]
        ];
        
    }
    
    sevensegmentDrawSegment(startx, starty, segment, scale) {
        var coords = this.segmentcoords[segment - 1];
        var isfirst = 1;
        this.ctx.beginPath();
        for(var i = 0; i < coords.length; i = i + 2) {
            var x = coords[i];
            var y = coords[i + 1];
            
            if(x == -1 && y == -1) {
                this.ctx.closePath();
                this.ctx.fill();
                this.ctx.stroke();
                this.ctx.beginPath();
                isfirst = 1;
                continue;
            }
            
            x = (x - 20) * scale / 16;
            y = (y - 15) * scale / 16;
            
            x = x + startx;
            y = y + starty;
            
            if(isfirst) {
                this.ctx.moveTo(x, y);
                isfirst = 0;
            } else {
                this.ctx.lineTo(x, y);
            }
        }
        this.ctx.closePath();
        this.ctx.fill();
        this.ctx.stroke();
        return;
    }
    
    sevensegmentDrawDigit(x, y, digit, scale) {
        var segments = '';
        
        if(digit === ' ') {
            segments = "";
        } else if(digit === '0') {
            segments = "123456";
        } else if(digit === '1') {
            segments = "35";
        } else if(digit === '2') {
            segments = "13746";
        } else if(digit === '3') {
            segments = "13756";
        } else if(digit === '4') {
            segments = "2735";
        } else if(digit === '5') {
            segments = "12756";
        } else if(digit === '6') {
            segments = "127456";
        } else if(digit === '7') {
            segments = "135";
        } else if(digit === '8') {
            segments = "1234567";
        } else if(digit === '9') {
            segments = "123567";
        } else if(digit === '0') {
            segments = "123456";
        } else if(digit === '.') {
            segments = '8';
        } else if(digit === ':') {
            segments = "9";
        } else if(digit === '-') {
            segments = "7";
        }
        
        var parts = segments.split('');
        var i;
        for(i = 0; i < parts.length; i++) {
            this.sevensegmentDrawSegment(x, y, parts[i], scale);
        }
        
        return;
    }
    
    sevensegmentDrawText(x, y, seventext, scale) {
        var parts = seventext.split('');//, $datestring;
        var i;
        for(i = 0; i < parts.length; i++) {
            this.sevensegmentDrawDigit(x + (i * 11 * scale), y, parts[i], scale);
        }
        
        return;
    }

}

