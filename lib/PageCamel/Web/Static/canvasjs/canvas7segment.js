class Canvas7Segment{
    constructor(canvas) {
        this.canvas = canvas;
        
        this.ctx = document.getElementById(this.canvas).getContext('2d');
        
        this.buttonlist = [];
        
        $('#' + this.canvas).on('click', this.checkButtonClick);
    }
    
    sevensegmentDrawSegment(x, y, segment, scale) {
        if(segment === '1') {
            this.ctx.fillRect(x, y, 5 * scale, 1 * scale);
        } else if(segment === '2') {
            this.ctx.fillRect(x, y, 1 * scale, 5 * scale);
        } else if(segment === '3') {
            this.ctx.fillRect(x + (5 * scale), y, 1 * scale, 5 * scale);
        } else if(segment === '4') {
            this.ctx.fillRect(x, y + (5 * scale), 1 * scale, 5 * scale);
        } else if(segment === '5') {
            this.ctx.fillRect(x + (5 * scale), y + (5 * scale), 1 * scale, 5 * scale);
        } else if(segment === '6') {
            this.ctx.fillRect(x, y + (10 * scale), 5 * scale, 1 * scale);
        } else if(segment === '7') {
            this.ctx.fillRect(x, y + (5 * scale), 5 * scale, 1 * scale);
        } else if(segment === '8') {
            this.ctx.fillRect(x + (7 * scale), y + (8 * scale), 2 * scale, 2 * scale);
        } else if(segment === '9') {
            this.ctx.fillRect(x + (2 * scale), y + (2 * scale), 1 * scale, 1 * scale);
            this.ctx.fillRect(x + (2 * scale), y + (7 * scale), 1 * scale, 1 * scale);
        }
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
            segments = "12375";
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
            this.sevensegmentDrawDigit(x + (i * 13 * scale), y, parts[i], scale);
        }
        
        return;
    }

}

