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
                /*if (circle.table_active == true) {
                    circle.border_width = 5;
                    circle.border = '#ff0000';
                }
                else {
                    circle.border_width = 0;
                    circle.border = '#000000';
                }*/
                ctx.font = circle.font_size + 'px Everson Mono';
                ctx.strokeStyle = circle.border;
                ctx.lineWidth = circle.border_width;
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
                    if (!circle.displaytext.includes("\n")) {
                        var text_width = ctx.measureText(circle.displaytext).width;
                        if (circle.align == 'right') {
                            //align text right
                            ctx.fillText(circle.displaytext, circle.x + circle.width - text_width - 8, circle.y + (circle.height / 2) + circle.font_size / 3.3);
                        }
                        else if (circle.align == 'left') {
                            //align text left
                            ctx.fillText(circle.displaytext, circle.x + 8, circle.y + (circle.height / 2) + circle.font_size / 3.3);
                        }
                        else {
                            //align text center
                            ctx.fillText(circle.displaytext, circle.x + (circle.width - text_width) / 2, circle.y + (circle.height / 2) + circle.font_size / 3.3);
                        }
                    } else {
                        var blines = circle.displaytext.split("\n");
                        var yoffs = circle.y + ((circle.height / 2) - (9 * (blines.length - 1)));
                        for (var j = 0; j < blines.length; j++) {
                            if (circle.align == 'right') {
                                blines[j].replace("\n", '');
                                var text_width = ctx.measureText(blines[j]).width;
                                ctx.fillText(blines[j], circle.x + circle.width - text_width - 8, yoffs);
                            }
                            else {
                                blines[j].replace("\n", '');
                                ctx.fillText(blines[j], circle.x + 8, yoffs);
                            }
                            yoffs = yoffs + 18;
                        }
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