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
        if (options.direction == 'down') {
            options.point1_x = 0;
            options.point1_y = 0;
            options.point2_x = options.height;
            options.point2_y = 0;
            options.point3_x = options.height / 2;
            options.point3_y = options.height;
        } else if (options.direction == 'up') {
            options.point1_x = 0;
            options.point1_y = options.height;
            options.point2_x = options.height;
            options.point2_y = options.height;
            options.point3_x = options.height / 2;
            options.point3_y = 0;
        } else if (options.direction == 'right') {
            options.point1_x = 0;
            options.point1_y = 0;
            options.point2_x = options.height;
            options.point2_y = options.height / 2;
            options.point3_x = 0;
            options.point3_y = options.height;
        } else if (options.direction == 'left') {
            options.point1_x = options.height;
            options.point1_y = 0;
            options.point2_x = options.height;
            options.point2_y = options.height;
            options.point3_x = 0;
            options.point3_y = options.height / 2;
        }
        options.a_x = options.x + options.width / 2 - options.height / 2;
        options.button.add(options);
        this.arrowbuttons.push(options);
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