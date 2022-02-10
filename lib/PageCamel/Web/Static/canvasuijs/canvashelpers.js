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
    ctx.stroke();
}

function drawArrow(ctx, x, y, width, height, direction) {
    var point1_x;
    var point1_y;
    var point2_x;
    var point2_y;
    var point3_x;
    var point3_y;
    if (direction == 'down') {
        point1_x = 0;
        point1_y = 0;
        point2_x = width;
        point2_y = 0;
        point3_x = width / 2;
        point3_y = height;
    } else if (direction == 'up') {
        point1_x = 0;
        point1_y = height;
        point2_x = width;
        point2_y = height;
        point3_x = width / 2;
        point3_y = 0;
    } else if (direction == 'right') {
        point1_x = 0;
        point1_y = 0;
        point2_x = width;
        point2_y = height / 2;
        point3_x = 0;
        point3_y = height;
    } else if (direction == 'left') {
        point1_x = width;
        point1_y = 0;
        point2_x = width;
        point2_y = height;
        point3_x = 0;
        point3_y = height / 2;
    } else {
        console.log("Arrow direction " + direction + " unknown");
        return "";
    }

    ctx.beginPath();
    ctx.moveTo(x + point1_x, y + point1_y);
    ctx.lineTo(x + point2_x, y + point2_y);
    ctx.lineTo(x + point3_x, y + point3_y);
    ctx.fill();
}