class UIArrow {
    constructor() {
        this.arrows = [];
    }
    add(options) {
        //this.arrows.push(options);
        var point1_x;
        var point1_y;
        var point2_x;
        var point2_y;
        var point3_x;
        var point3_y;
        if (options.direction == 'down') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.width;
            point2_y = 0;
            point3_x = options.width / 2;
            point3_y = options.height;
        } else if (options.direction == 'up') {
            point1_x = 0;
            point1_y = options.height;
            point2_x = options.width;
            point2_y = options.height;
            point3_x = options.width / 2;
            point3_y = 0;
        } else if (direction == 'right') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.width;
            point2_y = options.height / 2;
            point3_x = 0;
            point3_y = options.height;
        } else if (direction == 'left') {
            point1_x = options.width;
            point1_y = 0;
            point2_x = options.width;
            point2_y = options.height;
            point3_x = 0;
            point3_y = options.height / 2;
        }
        this.arrows.push({
            point1_x: point1_x,
            point1_y: point1_y,
            point2_x: point2_x,
            point2_y: point2_y,
            point3_x: point3_x,
            point3_y: point3_y,
            x: options.x,
            y: options.y,
        })
        return options;
    }
    render(ctx) {
        for (var i in this.arrows) {
            var arrow = this.arrows[i];
            ctx.beginPath();
            ctx.moveTo(arrow.x + arrow.point1_x, arrow.y + arrow.point1_y);
            ctx.lineTo(arrow.x + arrow.point2_x, arrow.y + arrow.point2_y);
            ctx.lineTo(arrow.x + arrow.point3_x, arrow.y + arrow.point3_y);
            ctx.fill();

        }
    }
    onClick(x, y) {
        return;
    }
    onHover(x, y) {
        return;
    }
    onMouseDown(x, y) {
        return;
    }
    onMouseUp(x, y) {
        return;
    }
    find(name) {
        return;
    }
    clear(){
        this.arrows = [];
    }
}