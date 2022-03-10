class UICircle {
    constructor(canvas) {
        this.canvas = canvas;
        this.circles = [];
    }
    add(options) {
        this.circles.push(options);
        return options;
    }
    drawEllipse(ctx, x, y, center_x, center_y, width, height, angle) {
        var radius_y = height / 2;
        var radius_x = width / 2;
        var ellipse_center_x = x + radius_x;
        var ellipse_center_y = y + radius_y;
        ctx.fillStyle = '#0000FF';
        ctx.strokeStyle = '#0579ff';
        ctx.save(); //saves the state of canvas
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        ctx.translate(center_x, center_y);
        ctx.rotate(angle * Math.PI / 180);
        ctx.translate(-center_x, -center_y)
        ctx.beginPath();
        ctx.ellipse(ellipse_center_x, ellipse_center_y, radius_x, radius_y, 0, 0, 2 * Math.PI);
        ctx.fill();
        ctx.stroke();
        ctx.restore(); //restore the state of canvas

    }
    render(ctx) {
        for (var i in this.circles) {
            var circle = this.circles[i];

            this.drawEllipse(ctx, circle.x, circle.y, circle.center_x, circle.center_y, circle.width, circle.height, circle.angle);
        }
    }
    onClick(x, y) {
        return;
    }
    onMouseDown(x, y) {
        return;
    }
    onMouseUp(x, y) {
        return;
    }
    onMouseMove(x, y) {
        return;
    }
    find(name) {
        return;
    }
    clear() {
        this.circles = [];
    }
}