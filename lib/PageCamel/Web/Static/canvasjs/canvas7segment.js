class Canvas7Segment{
    constructor(canvas) {
        this.canvas = canvas;
        
        this.ctx = document.getElementById(this.canvas).getContext('2d');
        
        this.buttonlist = [];
        
        this.checkButtonClick = this.checkButtonClick.bind(this);
        
        $('#' + this.canvas).on('click', this.checkButtonClick);
    }
    
    sevensegmentDrawSegment(ctx, x, y, segment, scale) {
        if(segment === '1') {
            ctx.fillRect(x, y, 5 * scale, 1 * scale);
        } else if(segment === '2') {
            ctx.fillRect(x, y, 1 * scale, 5 * scale);
        } else if(segment === '3') {
            ctx.fillRect(x + (5 * scale), y, 1 * scale, 5 * scale);
        } else if(segment === '4') {
            ctx.fillRect(x, y + (5 * scale), 1 * scale, 5 * scale);
        } else if(segment === '5') {
            ctx.fillRect(x + (5 * scale), y + (5 * scale), 1 * scale, 5 * scale);
        } else if(segment === '6') {
            ctx.fillRect(x, y + (10 * scale), 5 * scale, 1 * scale);
        } else if(segment === '7') {
            ctx.fillRect(x, y + (5 * scale), 5 * scale, 1 * scale);
        } else if(segment === '8') {
            ctx.fillRect(x + (7 * scale), y + (8 * scale), 2 * scale, 2 * scale);
        } else if(segment === '9') {
            ctx.fillRect(x + (2 * scale), y + (2 * scale), 1 * scale, 1 * scale);
            ctx.fillRect(x + (2 * scale), y + (7 * scale), 1 * scale, 1 * scale);
        }
    }
    
    sevensegmentDrawDigit(ctx, x, y, digit, scale) {
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
            sevensegmentDrawSegment(ctx, x, y, parts[i], scale);
        }
        
        return;
    }
    
    sevensegmentDrawText(ctx, x, y, seventext, scale) {
        var xlen = seventext.length * 12 + 3;
        

        var parts = seventext.split('');//, $datestring;
        var i;
        for(i = 0; i < parts.length; i++) {
            sevensegmentDrawDigit(ctx, x + (i * 13 * scale), y, parts[i], scale);
        }
        
        return;
    }

}

