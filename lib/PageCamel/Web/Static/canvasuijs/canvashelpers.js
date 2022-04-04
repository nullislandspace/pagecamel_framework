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
        if (keycode >= 48 && keycode <= 57) {
            char = keycode - 48;
        }
        if (keycode >= 96 && keycode <= 105) {
            char = keycode - 96;
        }
        if (char !== undefined) {
            e.preventDefault();
        }
        return char;
    }
}
