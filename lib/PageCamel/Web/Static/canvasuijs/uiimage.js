class UIImage {
    constructor(canvas) {
        this.canvas = canvas;
        this.images = [];
    }
    add(options) {
        if (options.active === undefined) {
            options.active = true;
        }
        this.images.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.images) {
            var image = this.images[i];
            if (image.active) {
                /*if (image.table_active == true) {
                    image.border_width = 5;
                    image.border = '#ff0000';
                }
                else {
                    image.border_width = 0;
                    image.border = '#000000';
                }*/
                ctx.font = image.font_size + 'px Everson Mono';
                ctx.strokeStyle = image.border;
                ctx.lineWidth = image.border_width;
                var grd;
                if (image.grd_type == 'horizontal') {
                    grd = ctx.createLinearGradient(image.x, image.y, image.x + image.width, image.y);
                }
                else if (image.grd_type == 'vertical') {
                    grd = ctx.createLinearGradient(image.x, image.y, image.x, image.y + image.height);
                }
                if (image.grd_type) {
                    var step_size = 1 / image.background.length;

                    for (var j in image.background) {
                        grd.addColorStop(step_size * j, image.background[j]);
                        ctx.fillStyle = grd;

                    }
                }
                if (image.background.length == 1) {
                    ctx.fillStyle = image.background[0];
                }
                ctx.save(); //saves the state of canvas
                ctx.translate(image.center_x, image.center_y);
                ctx.rotate(image.angle * Math.PI / 180);
                ctx.translate(-image.center_x, -image.center_y)
                ctx.beginPath();
                ctx.drawImage(image.nextImage, image.x, image.y, image.width, image.height);
                ctx.fill();
                if (image.border_width != 0 && image.border_width != undefined) {
                    ctx.strokeRect(image.x, image.y, image.width, image.height);
                }
                ctx.restore(); //restore the state of canvas
                ctx.fillStyle = image.foreground;
                ctx.strokeStyle = image.foreground;
                if (image.displaytext) {
                    if (!image.displaytext.includes("\n")) {
                        var text_width = ctx.measureText(image.displaytext).width;
                        if (image.align == 'right') {
                            //align text right
                            ctx.fillText(image.displaytext, image.x + image.width - text_width - 8, image.y + (image.height / 2) + image.font_size / 3.3);
                        }
                        else if (image.align == 'left') {
                            //align text left
                            ctx.fillText(image.displaytext, image.x + 8, image.y + (image.height / 2) + image.font_size / 3.3);
                        }
                        else {
                            //align text center
                            ctx.fillText(image.displaytext, image.x + (image.width - text_width) / 2, image.y + (image.height / 2) + image.font_size / 3.3);
                        }
                    } else {
                        var blines = image.displaytext.split("\n");
                        var yoffs = image.y + ((image.height / 2) - (9 * (blines.length - 1)));
                        for (var j = 0; j < blines.length; j++) {
                            if (image.align == 'right') {
                                blines[j].replace("\n", '');
                                var text_width = ctx.measureText(blines[j]).width;
                                ctx.fillText(blines[j], image.x + image.width - text_width - 8, yoffs);
                            }
                            else {
                                blines[j].replace("\n", '');
                                ctx.fillText(blines[j], image.x + 8, yoffs);
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
        this.images = [];
    }
}