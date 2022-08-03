class UIArrowButton {
    constructor(canvas) {
        this.arrowbuttons = [];
        
    }
    add(options) {
        /* required: x: number, y: number, width: number, 
        height: number, direction: String ('up', 'down', 'left', 'right'), 
        background: ['#000000', '#000000'], callback: function, foreground: '#000000',
        
        optional: 
        border_width: number, border_radius: number, font_size: number, 
        hover_border: '#000000', gradient_type: String ('horizontal', 'vertical')
        border: '#000000', align: String ('left', 'right', 'center'), displaytext: String */
        options.button = new UIButton();
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
        } else if (options.direction == 'right') {
            point1_x = 0;
            point1_y = 0;
            point2_x = options.height;
            point2_y = options.height / 2;
            point3_x = 0;
            point3_y = options.height;
        } else if (options.direction == 'left') {
            point1_x = options.height;
            point1_y = 0;
            point2_x = options.height;
            point2_y = options.height;
            point3_x = 0;
            point3_y = options.height / 2;
        }
        options.button.add(options);
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
        });
        return options;
    }
    render(ctx) {
        for (var i in this.arrowbuttons) {
            var arrowbutton = this.arrowbuttons[i];
            arrowbutton.button.render(ctx);
            ctx.beginPath();
            ctx.moveTo(arrowbutton.a_x + arrowbutton.point1_x, arrowbutton.y + arrowbutton.point1_y);
            ctx.lineTo(arrowbutton.a_x + arrowbutton.point2_x, arrowbutton.y + arrowbutton.point2_y);
            ctx.lineTo(arrowbutton.a_x + arrowbutton.point3_x, arrowbutton.y + arrowbutton.point3_y);
            ctx.fill();
        }

    }
    onClick(x, y) {
        for (var arrowbutton of this.arrowbuttons) {
            arrowbutton.button.onClick(x, y);
        }
    }
    onMouseDown(x, y) {
        for (var arrowbutton of this.arrowbuttons) {
            arrowbutton.button.onMouseDown(x, y);
        }
    }
    onMouseUp(x, y) {
        for (var arrowbutton of this.arrowbuttons) {
            arrowbutton.button.onMouseUp(x, y);
        }
    }
    onMouseMove(x, y) {
        for (var arrowbutton of this.arrowbuttons) {
            arrowbutton.button.onMouseMove(x, y);
        }
    }
    find(name) {
        for (var arrowbutton of this.arrowbuttons) {
            arrowbutton.button.find(name);
        }
    }
    clear() {
        this.arrowbuttons = [];
    }
}
canvasuijs.addType('ArrowButton', UIArrowButton);