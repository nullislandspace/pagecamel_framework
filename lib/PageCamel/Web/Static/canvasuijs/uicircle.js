class UICircle {
    constructor(canvas) {
        this.canvas = canvas;
        this.circles = [];
    }
    add(options) {
        if (options.active === undefined) {
            options.active = true;
        }
        this.circles.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.circles) {
            var circle = this.circles[i];
            if (circle.active) {
                ctx.font = circle.font_size +  'px ' + font_name;
                if (circle.highlight && (circle.main_highlight != circle.displaytext || circle.displaytext === undefined)) {
                    ctx.strokeStyle = '#ff0000';
                    ctx.lineWidth = 8;
                }
                else if (circle.main_highlight != circle.displaytext || circle.displaytext === undefined) {
                    ctx.strokeStyle = circle.border;
                    ctx.lineWidth = circle.border_width;
                }
                else if (circle.displaytext !== undefined) {
                    ctx.strokeStyle = '#00ffff';
                    ctx.lineWidth = 8;
                }
                var grd;
                if (circle.grd_type == 'horizontal') {
                    grd = ctx.createLinearGradient(circle.x, circle.y, circle.x + circle.width, circle.y);
                }
                else if (circle.grd_type == 'vertical') {
                    grd = ctx.createLinearGradient(circle.x, circle.y, circle.x, circle.y + circle.height);
                }
                if (circle.grd_type) {
                    var step_size = 1 / circle.background.length;

                    for (var j in circle.background) {
                        grd.addColorStop(step_size * j, circle.background[j]);
                        ctx.fillStyle = grd;

                    }
                }
                if (circle.background.length == 1) {
                    ctx.fillStyle = circle.background[0];
                }
                var radius_y = circle.height / 2;
                var radius_x = circle.width / 2;
                var ellipse_center_x = circle.x + radius_x;
                var ellipse_center_y = circle.y + radius_y;

                ctx.save(); //saves the state of canvas
                ctx.translate(circle.center_x, circle.center_y);
                ctx.rotate(circle.angle * Math.PI / 180);
                ctx.translate(-circle.center_x, -circle.center_y)
                ctx.beginPath();
                ctx.ellipse(ellipse_center_x, ellipse_center_y, radius_x, radius_y, 0, 0, 2 * Math.PI);
                ctx.fill();
                if (circle.border_width != 0 && circle.border_width != undefined) {
                    ctx.stroke();
                }
                ctx.restore(); //restore the state of canvas
                ctx.fillStyle = circle.foreground;
                ctx.strokeStyle = circle.foreground;
                if (circle.displaytext) {
                    if (!Array.isArray(circle.displaytext)) { // check if it's an array
                        circle.displaytext = [circle.displaytext];
                    }
                    var new_displaytext = [];
                    for (var j in circle.displaytext) {
                        if (circle.border_width > 0) {
                            var new_lines = autoLineBreak(ctx, circle.displaytext[j], circle.width - circle.border_width * 2);
                        } else {
                            var new_lines = autoLineBreak(ctx, circle.displaytext[j], circle.width);
                        }
                        if (new_lines.length > 0) {
                            new_displaytext = [...new_displaytext, ...new_lines];
                        }
                    }
                    var yoffs = circle.y + (circle.height / 2) + circle.font_size / 3.3;
                    if (new_displaytext.length > 1) {
                        yoffs = circle.y + circle.height / 2 - ((new_displaytext.length - 1) * (circle.font_size * 0.80)) / 2;
                    }
                    for (j = 0; j < new_displaytext.length; j++) {
                        var text_width = ctx.measureText(new_displaytext[j]).width;
                        if (circle.align == 'right') {
                            //align text right
                            ctx.fillText(new_displaytext[j], circle.x + circle.width - text_width - 8, yoffs);
                        }
                        else if (circle.align == 'left') {
                            //align text left
                            ctx.fillText(new_displaytext[j], circle.x + 8, yoffs);
                        }
                        else {
                            //align text center
                            ctx.fillText(new_displaytext[j], circle.x + (circle.width / 2) - (text_width / 2), yoffs);
                        }
                        yoffs = yoffs + circle.font_size * 1.1;
                    }
                }
            }
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
canvasuijs.addType('Circle', UICircle);