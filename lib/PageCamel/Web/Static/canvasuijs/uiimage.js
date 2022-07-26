class ImageHandler {
    constructor() {
        this.images = {};
        this.queue = [];

    }
    getImage(hash) {
        if (this.images[hash]) {
            return this.images[hash];
        }
        for (var i = 0; i < this.queue.length; i++) {
            if (this.queue[i] == hash) {
                return;
            }
        }

        if (!wsconnected) {
            return;
        }

        sendMessage({
            type: 'GETIMAGE',
            id: hash
        });
        this.queue.push(hash);
    }
    setImage(image_data, hash) {
        if (this.images[hash]) {
            return;
        }
        if (!wsconnected) {
            return;
        }
        sendMessage({
            type: 'SETIMAGE',
            id: hash,
            data: image_data
        });
        this.images[hash] = image_data;
    }
    gotMessage(message) {
        if (message.type == 'IMAGE') {
            if (this.images[message.id] === undefined) {
                this.images[message.id] = message.data;
                //remove from queue
                for (var i = 0; i < this.queue.length; i++) {
                    if (this.queue[i] == message.id) {
                        this.queue.splice(i, 1);
                        break;
                    }
                }
                triggerRepaint();
            }
        }
    }
}

class UIImage {
    // UI Image Element
    constructor(canvas) {
        this.canvas = canvas;
        this.images = [];
    }
    add(options) {
        if (options.active === undefined) {
            options.active = true;
        }
        if (options.image_hash === undefined) {
            if (options.image_data !== undefined) {
                options.image_hash = sha256_digest(options.image_data);
                image_handler.setImage(options.image_data, options.image_hash);
            } else if (options.image !== undefined && options.image.src !== undefined) {
                options.image_hash = sha256_digest(options.image.src);
                image_handler.setImage(options.image.src, options.image_hash);
            }
        }
        if (options.image === undefined && options.image_data !== undefined) {
            options.image = new Image();
            options.image.src = options.image_data;
        }

        this.images.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.images) {
            var image = this.images[i];
            if (image.active) {
                if (image.highlight && (image.main_highlight != image.displaytext || image.displaytext === undefined)) {
                    ctx.strokeStyle = '#ff0000';
                    ctx.lineWidth = 8;
                }
                else if (image.main_highlight != image.displaytext || image.displaytext === undefined) {
                    ctx.strokeStyle = image.border;
                    ctx.lineWidth = image.border_width;
                }
                else {
                    ctx.strokeStyle = '#00ffff';
                    ctx.lineWidth = 8;
                }
                ctx.font = image.font_size + 'px Everson Mono';
                ctx.save(); //saves the state of canvas
                ctx.translate(image.center_x, image.center_y);
                ctx.rotate(image.angle * Math.PI / 180);
                ctx.translate(-image.center_x, -image.center_y)
                ctx.beginPath();
                if (image.image !== undefined) {
                    ctx.drawImage(image.image, image.x, image.y, image.width, image.height);
                    if (image_handler.images[image.image_hash] === undefined) {
                        image_handler.setImage(image.image.src, image.image_hash);
                    }
                } else if (image.image_hash !== undefined) {
                    if (image_handler.images[image.image_hash] !== undefined) { //check if imagehandler already has the image
                        image.image = new Image();
                        image.image.src = image_handler.images[image.image_hash];
                        ctx.drawImage(image.image, image.x, image.y, image.width, image.height);
                        image.image_data = image_handler.images[image.image_hash];
                    }
                    else {
                        image_handler.getImage(image.image_hash);
                    }
                }

                ctx.fill();
                if (image.border_width != 0 && image.border_width != undefined) {
                    ctx.strokeRect(image.x, image.y, image.width, image.height);
                }
                ctx.restore(); //restore the state of canvas
                ctx.fillStyle = image.foreground;
                ctx.strokeStyle = image.foreground;
                if (image.displaytext) {
                    if (!Array.isArray(image.displaytext)) { // check if it's an array
                        image.displaytext = [image.displaytext];
                    }
                    var new_displaytext = [];
                    for (var j in image.displaytext) {
                        if (image.border_width > 0) {
                            var new_lines = autoLineBreak(ctx, image.displaytext[j], image.width - image.border_width * 2);
                        } else {
                            var new_lines = autoLineBreak(ctx, image.displaytext[j], image.width);
                        }
                        if (new_lines.length > 0) {
                            new_displaytext = [...new_displaytext, ...new_lines];
                        }
                    }
                    var yoffs = image.y + (image.height / 2) + image.font_size / 3.3;
                    if (new_displaytext.length > 1) {
                        yoffs = image.y + image.height / 2 - ((new_displaytext.length - 1) * (image.font_size * 0.80)) / 2;
                    }
                    for (j = 0; j < new_displaytext.length; j++) {
                        var text_width = ctx.measureText(new_displaytext[j]).width;
                        if (image.align == 'right') {
                            //align text right
                            ctx.fillText(new_displaytext[j], image.x + image.width - text_width - 8, yoffs);
                        }
                        else if (image.align == 'left') {
                            //align text left
                            ctx.fillText(new_displaytext[j], image.x + 8, yoffs);
                        }
                        else {
                            //align text center
                            ctx.fillText(new_displaytext[j], image.x + (image.width / 2) - (text_width / 2), yoffs);
                        }
                        yoffs = yoffs + image.font_size * 1.1;
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
canvasuijs.addType('Image', UIImage);