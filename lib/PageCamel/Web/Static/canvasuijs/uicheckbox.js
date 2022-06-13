class UICheckBox {
    constructor(canvas) {
        this.checkboxes = [];
        canvas = canvas.substring(1, canvas.length);
        this.ctx = document.getElementById(canvas).getContext('2d');
    }
    add(options) {
        if (options.displaytext !== undefined) {
            this.ctx.font = options.font_size + 'px Courier';
            options.text_width = this.ctx.measureText(options.displaytext).width;
        }
        if (options.checked === undefined) {
            options.checked = false
        }

        this.checkboxes.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.checkboxes) {
            var checkbox = this.checkboxes[i];

            ctx.fillStyle = checkbox.background[0];
            ctx.strokeStyle = checkbox.border;
            roundRect(ctx, checkbox.x, checkbox.y, checkbox.width, checkbox.height, checkbox.border_radius, checkbox.border_width);
            ctx.stroke();
            if (checkbox.checked) {
                ctx.fillStyle = '#00ff00';
                ctx.font = checkbox.height * 1.3 - checkbox.border_width + 'px Courier';
                ctx.fillText('✔', checkbox.x, checkbox.y + checkbox.height - checkbox.border_width);
            }
            if (checkbox.displaytext !== undefined) {
                ctx.fillStyle = checkbox.foreground;
                ctx.font = checkbox.font_size + 'px Courier';
                this.ctx.font = checkbox.font_size + 'px Courier';
                if (checkbox.align == 'left') {
                    checkbox.text_width = this.ctx.measureText(checkbox.displaytext).width;
                    ctx.fillText(checkbox.displaytext, checkbox.x - checkbox.text_width - 5, checkbox.y + (checkbox.height / 2) + checkbox.font_size / 3.3);
                }
                else {
                    ctx.fillText(checkbox.displaytext, checkbox.x + checkbox.width + checkbox.border_width + 5, checkbox.y + (checkbox.height / 2) + checkbox.font_size / 3.3);
                }

            }

        }
    }
    onClick(x, y) {
        return;
    }
    onMouseDown(x, y) {
        for (var i in this.checkboxes) {
            var checkbox = this.checkboxes[i];
            var startx = checkbox.x;
            var endx = checkbox.x + checkbox.width;
            if (checkbox.align == 'left' && checkbox.displaytext !== undefined) {
                startx = checkbox.x - checkbox.text_width - 5
            }
            else if (checkbox.displaytext !== undefined) {
                endx = checkbox.x + checkbox.width + 5 + checkbox.text_width
            }
            var starty = checkbox.y;
            var endy = starty + checkbox.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy) {
                checkbox.mousedown = true;
                return;
            }
        }

        return;
    }
    onMouseUp(x, y) {
        for (var i in this.checkboxes) {
            var checkbox = this.checkboxes[i];
            var startx = checkbox.x;
            var endx = checkbox.x + checkbox.width;
            if (checkbox.align == 'left' && checkbox.displaytext !== undefined) {
                startx = checkbox.x - checkbox.text_width - 5

            }
            else if (checkbox.displaytext !== undefined) {
                endx = checkbox.x + checkbox.width + 5 + checkbox.text_width
            }
            var starty = checkbox.y;
            var endy = starty + checkbox.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy && checkbox.mousedown) {
                checkbox.checked = !checkbox.checked;
                checkbox.callback(checkbox.checked);
                triggerRepaint();
            }
            checkbox.mousedown = false;
        }
    }
    onMouseMove(x, y) {
        return;
    }
    clear() {
        this.checkboxes = [];
    }
    find(name) {
        return;
    }
}
canvasuijs.addType('CheckBox', UICheckBox);