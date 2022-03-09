class UICircle {
    constructor(canvas) {
        this.canvas = canvas;
        this.circles = [];
    }
    add(options) {
        this.circles.push(options);
        return options;
    }
    drawEllipse(ctx, x, y, width, height) {
        var radius_y = height / 2;
        var radius_x = width / 2;
        var center_x = x + radius_x;
        var center_y = y + radius_y;
        ctx.fillSyle = 'blue';
        ctx.strokeStyle = '#0579ff';
        ctx.beginPath();
        
        ctx.fillStyle = '#0000FF';
        ctx.ellipse(center_x, center_y, radius_x, radius_y, 0, 0, 2 * Math.PI);
        ctx.fill();
        ctx.stroke();
    }
    render(ctx) {
        for (var i in this.circles) {
            var circle = this.circles[i];
            this.drawEllipse(ctx, circle.x, circle.y, circle.width, circle.height);
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