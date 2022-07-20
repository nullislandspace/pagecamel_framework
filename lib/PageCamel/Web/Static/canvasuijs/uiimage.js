class ImageHandler {
    constructor() {
        this.images = {};
        this.queue = [];

    }
    getImage(hash) {
        if (this.images[hash]) {
            return this.images[hash];
        }
        //check if it's in the queue and check if it's been there for too long
        for (var i = 0; i < this.queue.length; i++) {
            if (this.queue[i].hash == hash && this.queue[i].time_sent + 5000 > Date.now()) {
                return;
            }
            else if (this.queue[i].hash == hash) {
                this.queue.splice(i, 1);
            }
        }
        if (!wsconnected) {
            return;
        }

        sendMessage({
            type: 'GETIMAGE',
            id: hash
        });
        this.queue.push({ hash: hash, time_sent: Date.now() });
    }
    setImage(image_data, hash) {
        if (this.images[hash]) {
            return;
        }
        this.images[hash] = image_data;
        if (!wsconnected) {
            return;
        }
        sendMessage({
            type: 'SETIMAGE',
            id: hash,
            data: image_data
        });
    }
    gotMessage(message) {
        if (message.type == 'IMAGE') {
            this.images[message.id] = message.data;
            //remove from queue
            for (var i = 0; i < this.queue.length; i++) {
                if (this.queue[i].hash == message.id) {
                    this.queue.splice(i, 1);
                    break;
                }
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
                } else if (image.image_hash !== undefined) {
                    if (image_handler.images[image.image_hash] !== undefined) {
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
canvasuijs.addType('Image', UIImage);