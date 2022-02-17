class UIArrowButton {
    constructor() {
        this.arrowbuttons = [];
        this.button = new UIButton();
    }
    add(options) {
        //this.arrowbuttons.push(options);
        var point1_x;
        var point1_y;
        var point2_x;
        var point2_y;
        var point3_x;
        var point3_y;
        if (options.direction == 'down') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.height;
            point2_y = 0;
            point3_x = options.height / 2;
            point3_y = options.height;
        } else if (options.direction == 'up') {
            point1_x = 0;
            point1_y = options.height;
            point2_x = options.height;
            point2_y = options.height;
            point3_x = options.height / 2;
            point3_y = 0;
        } else if (direction == 'right') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.height;
            point2_y = options.height / 2;
            point3_x = 0;
            point3_y = options.height;
        } else if (direction == 'left') {
            point1_x = options.height;
            point1_y = 0;
            point2_x = options.height;
            point2_y = options.height;
            point3_x = 0;
            point3_y = options.height / 2;
        }
        this.arrowbuttons.push({
            point1_x: point1_x,
            point1_y: point1_y,
            point2_x: point2_x,
            point2_y: point2_y,
            point3_x: point3_x,
            point3_y: point3_y,
            x: options.x,
            y: options.y,
            a_x: options.x + options.width / 2 - options.height / 2, // place arrow in center of button
        })
        this.button.add(options);
        return options;
    }
    render(ctx) {
        this.button.render(ctx);
        for (var i in this.arrowbuttons) {
            var arrowbutton = this.arrowbuttons[i];
            ctx.beginPath();
            ctx.moveTo(arrowbutton.a_x + arrowbutton.point1_x, arrowbutton.y + arrowbutton.point1_y);
            ctx.lineTo(arrowbutton.a_x + arrowbutton.point2_x, arrowbutton.y + arrowbutton.point2_y);
            ctx.lineTo(arrowbutton.a_x + arrowbutton.point3_x, arrowbutton.y + arrowbutton.point3_y);
            ctx.fill();

        }

    }
    onClick(x, y) {
        this.button.onClick(x, y);
    }
    onHover(x, y) {
        this.button.onHover(x, y);
    }
    onMouseDown(x, y) {
        this.button.onMouseDown(x, y);
    }
    onMouseUp(x, y) {
        this.button.onMouseUp(x, y);
    }
    find(name) {
        return;
    }
    clear() {
        this.arrowbuttons = [];
        this.button.clear();
    }
}