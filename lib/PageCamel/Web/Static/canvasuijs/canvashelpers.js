function roundRect(ctx, x, y, w, h, radius, line_width) {
    //round rectangle
    var r = x + w;
    var b = y + h;
    ctx.lineWidth = line_width;
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(r - radius, y);
    ctx.quadraticCurveTo(r, y, r, y + radius);
    ctx.lineTo(r, y + h - radius);
    ctx.quadraticCurveTo(r, b, r - radius, b);
    ctx.lineTo(x + radius, b);
    ctx.quadraticCurveTo(x, b, x, b - radius);
    ctx.lineTo(x, y + radius);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.fill();
    if (line_width > 0 && line_width != undefined) {
        ctx.stroke();
    }
}
function rotate(cx, cy, x, y, angle) {
    //calculate the new x and y coordinates after rotation
    var radians = (Math.PI / 180) * angle,
        cos = Math.cos(radians),
        sin = Math.sin(radians),
        nx = (cos * (x - cx)) + (sin * (y - cy)) + cx,
        ny = (cos * (y - cy)) - (sin * (x - cx)) + cy;
    return [nx, ny];
}
class GetPressedKeyChar {
    constructor() {
        this.uppercase = false
    }
    keyup(e) {
        //check if keycode is 16 (shift)
        var keycode = e.keyCode;
        if (keycode == 16) {
            this.uppercase = false;
        }
    }
    keydown(e) {
        //convert keycode to char
        var keycode = e.keyCode;
        var char;
        if (keycode == 16) {
            this.uppercase = true;
        }
        if (keycode >= 65 && keycode <= 90) {
            char = String.fromCharCode(keycode);
        }
        if (keycode == 186) {
            char = 'Ü';
        }
        if (keycode == 192) {
            char = 'Ö';
        }
        if (keycode == 222) {
            char = 'Ä';
        }
        if (!this.uppercase && char !== undefined) {
            char = char.toLowerCase();
        }
        if (keycode == 32) {
            char = ' ';
        }
        if (keycode == 8) {
            char = 'backspace';
        }
        if (keycode == 46) {
            char = 'delete';
        }
        if (keycode >= 48 && keycode <= 57) {
            char = keycode - 48;
        }
        if (keycode >= 96 && keycode <= 105) {
            char = keycode - 96;
        }
        if ((keycode == 188 || keycode == 108) && !this.uppercase) {
            char = ',';
        }
        if (char !== undefined) {
            e.preventDefault();
        }
        return char;
    }
}
function RGBToHex(r, g, b) {
    //convert rgb to hex
    var bin = r << 16 | g << 8 | b;
    return (function (h) {
        return new Array(7 - h.length).join("0") + h
    })(bin.toString(16).toUpperCase())
}
//create full hex
function fullHex(hex) {
    let r = hex.slice(1, 2);
    let g = hex.slice(2, 3);
    let b = hex.slice(3, 4);

    r = parseInt(r + r, 16);
    g = parseInt(g + g, 16);
    b = parseInt(b + b, 16);

    // return {r, g, b} 
    return { r, g, b };
}

//convert hex to rgb
function HexToRGB(hex) {
    //convert hex to rgb
    if (hex.length === 4) {
        return fullHex(hex);
    }

    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);

    // return {r, g, b} 
    return [r, g, b];
}
function isValidHexaCode(str) {
    if (str[0] != '#')
        return false;

    if (!(str.length == 4 || str.length == 7))
        return false;

    for (let i = 1; i < str.length; i++)
        if (!((str[i].charCodeAt(0) <= '0'.charCodeAt(0) && str[i].charCodeAt(0) <= 9)
            || (str[i].charCodeAt(0) >= 'a'.charCodeAt(0) && str[i].charCodeAt(0) <= 'f'.charCodeAt(0))
            || (str[i].charCodeAt(0) >= 'A'.charCodeAt(0) || str[i].charCodeAt(0) <= 'F'.charCodeAt(0))))
            return false;

    return true;
}
function getForegroundColor(hex_color) {
    //get foreground color based on background color
    var rgb_color = HexToRGB(hex_color);
    var foreground = (rgb_color[0] + rgb_color[1] + rgb_color[2]) / 3;
    if (foreground > 100) {
        foreground = 0;
    }
    else {
        foreground = 255
    }
    var hex_foreground = '#' + RGBToHex(foreground, foreground, foreground);
    return hex_foreground;
}

function centToEuros(cents) {
    //converts the cents String in euros without division
    var cents_str = String(cents);
    var isnegative = false;
    if (cents_str[0] == '-') {
        isnegative = true;
        cents_str = cents_str.substr(1, cents_str.length - 1);
    }

    while (cents_str.length < 3) {
        cents_str = '0' + cents_str;
    }
    var first_part = cents_str.substr(0, cents_str.length - 2);
    var last_part = ',' + cents_str.substr(-2);
    var new_first_part = '';
    for (var i = 0; i < Math.floor((first_part.length - 1) / 3); i++) {
        new_first_part = '.' + first_part.substr(first_part.length - (i + 1) * 3, 3) + new_first_part;
    }
    var euros = '';
    if (first_part.length % 3 != 0) {
        euros = first_part.substr(0, first_part.length % 3) + new_first_part + last_part;


    }
    else {
        euros = first_part.substr(0, 3) + new_first_part + last_part;
    }

    if (isnegative) {
        euros = '-' + euros;
    }

    return euros;
}
function eurosToCent(euros) {
    //converts euros with . as thousand separator and , as decimal separator to cents
    var euros_str = String(euros);
    euros_str = euros_str.replace(/\./g, '')
    //check if negative
    var isnegative = false;
    if (euros_str[0] == '-') {
        isnegative = true;
        euros_str = euros_str.substr(1, euros_str.length - 1);
    }
    var cents;
    if (euros.indexOf(',') != -1) {
        var euros_length = euros.length;
        var comma_position = euros.indexOf(',');
        var after_comma = euros_length - 1 - comma_position;
        var zeros_missing = 2 - after_comma;
        //add missing zeros to euros
        for (var i = 0; i < zeros_missing; i++) {
            euros_str += '0';
        }
        //remove , from euros
        euros_str = euros_str.replace(/,/g, '');
        cents = parseInt(euros_str);
    }
    else {
        cents = euros_str + '00';
    }
    if (isnegative) {
        cents = '-' + cents;
    }
    return parseInt(cents);
}
function getCanvasWidthHeight(canvas) {
    //get canvas width and height
    var _canvas = document.getElementById(canvas);
    var width = _canvas.width;
    var height = _canvas.height;
    return [width, height];
}
function setCanvasWindowSize(canvas) {
    //set Canvas Sizes based on screen size
    canvas.width = window.innerWidth * size_multiplier - 350;
    canvas.height = window.innerHeight * size_multiplier - 100;

    //check if canvas is too small
    if (canvas.width < 400) {
        canvas.width = 400;
    }
    if (canvas.height < 300) {
        canvas.height = 300;
    }
}
function autoLineBreak(ctx, text, maxWidth) {
    //automatically line breaks. Breaks preferably at spaces and if not possible at other places.
    var words = text.split(' ');
    var lines = [];
    var currentLine = '';
    for (var i = 0; i < words.length; i++) {
        var word = words[i];
        var wordWidth = ctx.measureText(word).width;
        var width = ctx.measureText(currentLine + word).width;
        if (wordWidth > maxWidth) { //if word is too long, break it up into multiple lines
            if (currentLine.length > 0) {
                lines.push(currentLine);
            }
            currentLine = '';
            var letters_width = 0;
            for (var j = 0; j < word.length; j++) {
                var letter = word[j];
                var letterWidth = ctx.measureText(letter).width;
                if (letters_width + letterWidth > maxWidth) {
                    lines.push(currentLine);
                    letters_width = 0;
                    currentLine = '';
                }
                currentLine += letter;
                letters_width += letterWidth;
            }
            currentLine += ' ';
        }
        else {
            if (width > maxWidth) { //if line is too long, break it and add word to next line
                lines.push(currentLine);
                currentLine = '';
            }
            currentLine += word + ' ';
        }
    }
    if (currentLine.length > 0) {
        if (currentLine[currentLine.length - 1] == ' ') {
            currentLine = currentLine.substr(0, currentLine.length - 1);
        }
        lines.push(currentLine);
    }
    return lines;
}
function getSizeMultiplier(min_size) {
    var sizeMultiplier = 1;
    if (window.innerWidth < min_size) {
        sizeMultiplier = min_size / window.innerWidth;
    }
    if (window.innerHeight * sizeMultiplier < min_size) {
        sizeMultiplier = min_size / window.innerHeight;
    }
    return sizeMultiplier;
}
class PercentageToPixel {
    constructor(max_value) {
        this.max_value = max_value;
    }
    getPixel(percentage) {
        return percentage * this.max_value / 100;
    }
}
function eventPropagation(to_extend, parents, children) {
    //propagates input events to child objects
    to_extend.onKeyDown = function (e) {
        for (var parent of parents) {
            for (var child of children) {
                parent[child].onKeyDown(e);
            }
        }
    }
    to_extend.onMouseDown = function (x, y) {
        for (var parent of parents) {
            for (var child of children) {
                parent[child].onMouseDown(x, y);
            }
        }
    }
    to_extend.onMouseUp = function (x, y) {
        for (var parent of parents) {
            for (var child of children) {
                parent[child].onMouseUp(x, y);
            }
        }
    }
    to_extend.onMouseMove = function (x, y) {
        for (var parent of parents) {
            for (var child of children) {
                parent[child].onMouseMove(x, y);
            }
        }
    }
    to_extend.onKeyUp = function (e) {
        for (var parent of parents) {
            for (var child of children) {
                parent[child].onKeyUp(e);
            }
        }
    }
}
