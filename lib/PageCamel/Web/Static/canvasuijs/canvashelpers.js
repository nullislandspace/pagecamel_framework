function roundRect(ctx, x, y, w, h, radius, line_width) {
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
        var keycode = e.keyCode;
        if (keycode == 16) {
            this.uppercase = false;
        }
    }
    keydown(e) {
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
function centToShowable(cents) {
    var cents_str = String(cents);
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
    return euros;
}
function objectsEqual(o1, o2) {
    if (o1 === o2) return true;
    // if both o1 and o2 are null or undefined and exactly the same

    if (!(o1 instanceof Object) || !(o2 instanceof Object)) return false;
    // if they are not strictly equal, they both need to be Objects

    if (o1.constructor !== o2.constructor) return false;
    // they must have the exact same prototype chain, the closest we can do is
    // test there constructor.

    for (var p in o1) {
        if (!o1.hasOwnProperty(p)) continue;
        // other properties were tested using o1.constructor === o2.constructor

        if (!o2.hasOwnProperty(p)) return false;
        // allows to compare o1[ p ] and o2[ p ] when set to undefined

        if (o1[p] === o2[p]) continue;
        // if they have the same strict value or identity then they are equal

        if (typeof (o1[p]) !== "object") return false;
        // Numbers, Strings, Functions, Booleans must be strictly equal

        if (!object_equals(o1[p], o2[p])) return false;
        // Objects and Arrays must be tested recursively
    }

    for (p in o2)
        if (o2.hasOwnProperty(p) && !o1.hasOwnProperty(p))
            return false;
    // allows o1[ p ] to be set to undefined

    return true;
}
function getCanvasWidthHeight(canvas) {
    var _canvas = document.getElementById(canvas);
    var width = _canvas.width;
    var height = _canvas.height;
    return [width, height];
}
function setCanvasWindowSize(canvas) {
    //set Canvas Sizes based on screen size
    if(window.screen.width > 1300){
        canvas.width = window.screen.width - 300;
    }
    else{
        canvas.width = window.screen.width;
    }
    if(window.screen.height > 1000){
        canvas.height = window.screen.height - 200;
    }
    else{
        canvas.height = window.screen.height;
    }
}