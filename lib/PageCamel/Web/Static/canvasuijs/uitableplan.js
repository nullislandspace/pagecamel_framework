class UITablePlan {
    constructor(canvas) {
        this.canvas = canvas;
        this.uitableplans = [];
        this.dragndrop = new UIDragNDrop(this.canvas);
        this.button = new UIButton(this.canvas);
        this.numpad = new UINumpad(this.canvas);
    }
    add(options) {
        options.editable = false;
        options.elements = [];
        options.draw = { mousedown_x: null, mousedown_y: null, mousemove_x: null, mousemove_y: null };
        options.redoable = [];
        options.undoable = [];
        options.rects = [];
        options.circles = [];
        options.ellipses = [];
        options.select = false;
        options.circle = false;
        options.rect = false;
        options.edit = () => {
            options.editable = true;
            this.update();
        }
        options.save = () => {
            options.editable = false;
            this.update();
        }
        options.changeRect = (data, uiItem) => {
            var i = data.index;
            options.rects[i].x = uiItem.x;
            options.rects[i].y = uiItem.y;
            options.rects[i].width = uiItem.width;
            options.rects[i].height = uiItem.height;
        }
        options.changeCircle = (data, uiItem) => {
            var i = data.index;
            options.circles[i].x = uiItem.x;
            options.circles[i].y = uiItem.y;
            options.circles[i].width = uiItem.width;
            options.circles[i].height = uiItem.height;
        }
        options.cancel = () => {
            options.editable = false;
            options.circle = false;
            options.rect = false;
            this.update();
        }
        options.selectTable = () => {
            $(this.canvas).css('cursor', 'default');
            options.circle = false;
            options.rect = false;
            options.select = true;
        }
        options.drawCircle = () => {
            $(this.canvas).css('cursor', 'crosshair');
            options.circle = true;
            options.select = false;
            options.rect = false;
        }
        options.drawRect = () => {
            $(this.canvas).css('cursor', 'crosshair');
            options.rect = true;
            options.select = false;
            options.circle = false;
        }
        this.uitableplans.push(options);
        this.update();
        return options;
    }
    update() {
        this.button.clear();
        this.numpad.clear();
        this.dragndrop.clear();
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.editable == false) {
                this.button.add({
                    displaytext: '🖉 Bearbeiten',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 20, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#009dff',
                    callback: uitableplan.edit
                });
                this.numpad.add({
                    show_keys: { x: true, ZWS: true },
                    background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000', grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
                    x: uitableplan.x + uitableplan.width - 210, y: uitableplan.y + uitableplan.height - 350 - 70, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
                    callback: buttonSendMessage,
                    callbackData: { key: "Numpad" }
                });
            }
            else {
                this.button.add({
                    displaytext: '➕⬜',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 215, y: uitableplan.y + 200, width: 100, height: 100, border_radius: 20, font_size: 40, hover_border: '#009dff',
                    callback: uitableplan.drawRect
                });
                this.button.add({
                    displaytext: "🖰",
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 215, y: uitableplan.y + 310, width: 100, height: 100, border_radius: 20, font_size: 40, hover_border: '#009dff',
                    callback: uitableplan.selectTable
                });
                this.button.add({
                    displaytext: '➕◯',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 105, y: uitableplan.y + 200, width: 100, height: 100, border_radius: 20, font_size: 40, hover_border: '#009dff',
                    callback: uitableplan.drawCircle
                });
                this.button.add({
                    displaytext: '🗙 Abbrechen',
                    background: ['#ff948c', '#ff1100',], foreground: '#000000', border: '#ff948c', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 170, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#ff1100',
                    callback: uitableplan.cancel
                });
                this.button.add({
                    displaytext: '💾 Speichern',
                    background: ['#39f500', '#32d600'], foreground: '#000000', border: '#39f500', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + uitableplan.width - 350, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#32d600',
                    callback: uitableplan.save
                });
                for (var j in uitableplan.rects) {
                    var rect = uitableplan.rects[j];
                    this.dragndrop.add({
                        displaytext: '0', group_id: i, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - 70,
                        background: ['#0d05ff'], foreground: '#000000', border: '#0579ff', border_width: 3, grd_type: 'vertical', editable: true,
                        x: rect.x, y: rect.y, width: rect.width, height: rect.height, font_size: 15, callbackData: { index: j },
                        callback: uitableplan.changeRect
                    })
                }
                for (var j in uitableplan.circles) {
                    var circle = uitableplan.circles[j];
                    this.dragndrop.add({
                        displaytext: '0', group_id: i, contain_x: uitableplan.x, contain_y: uitableplan.y, contain_width: uitableplan.width - 225, contain_height: uitableplan.height - 70,
                        background: ['#0d05ff'], foreground: '#000000', border: '#0579ff', border_width: 3, grd_type: 'vertical', editable: true, type: 'circle',
                        x: circle.x, y: circle.y, width: circle.width, height: circle.height, font_size: 15, callbackData: { index: j },
                        callback: uitableplan.changeCircle
                    })
                }
            }
        }
        triggerRepaint();
    }
    render(ctx) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            ctx.fillStyle = uitableplan.background[0];
            ctx.lineWidth = uitableplan.border_width;
            ctx.fillRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            ctx.fillStyle = '#A9A9A9';
            ctx.fillRect(uitableplan.x + uitableplan.border_width / 2, uitableplan.y + uitableplan.height - 70, uitableplan.width - uitableplan.border_width, 70 - uitableplan.border_width / 2);
            ctx.fillRect(uitableplan.x + uitableplan.width - 225, uitableplan.y + uitableplan.border_width / 2, 225 - uitableplan.border_width / 2, uitableplan.height - uitableplan.border_width);
            ctx.strokeStyle = uitableplan.border;
            ctx.strokeRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            if (uitableplan.draw.mousedown_x != null) {
                if (uitableplan.rect) {
                    ctx.fillStyle = '#0000FF';
                    ctx.fillRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                        uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
                }
                else if (uitableplan.circle) {
                    ctx.beginPath();
                    ctx.fillStyle = '#0000FF';
                    var ellipse_radius_x = (uitableplan.draw.mousedown_x - uitableplan.draw.mousemove_x) / 2;
                    var ellipse_radius_y = (uitableplan.draw.mousedown_y - uitableplan.draw.mousemove_y) / 2;
                    var ellipse_center_x = uitableplan.draw.mousedown_x + uitableplan.x - ellipse_radius_x;
                    var ellipse_center_y = uitableplan.draw.mousedown_y + uitableplan.y - ellipse_radius_y;
                    if (ellipse_radius_x < 0) {
                        ellipse_radius_x = (uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x) / 2
                        ellipse_center_x = uitableplan.draw.mousedown_x + uitableplan.x + ellipse_radius_x;
                    }
                    if (ellipse_radius_y < 0) {
                        ellipse_radius_y = (uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y) / 2
                        ellipse_center_y = uitableplan.draw.mousedown_y + uitableplan.y + ellipse_radius_y;
                    }
                    ctx.ellipse(ellipse_center_x, ellipse_center_y, ellipse_radius_x, ellipse_radius_y, 0, 0, 2 * Math.PI);
                    ctx.fill();

                }
            }
        }
        this.button.render(ctx);
        this.numpad.render(ctx);
        this.dragndrop.render(ctx);
    }
    onClick(x, y) {
        this.button.onClick(x, y);
        this.numpad.onClick(x, y);
        this.dragndrop.onClick(x, y);

    }

    onMouseDown(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (!uitableplan.circle && !uitableplan.rect && uitableplan.editable) {
                this.dragndrop.onMouseDown(x, y);
            }
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                if (x > uitableplan.x && x < uitableplan.x + uitableplan.width - 225 && y > uitableplan.y && y < uitableplan.y + uitableplan.height - 70) {
                    uitableplan.draw.mousedown_x = x - uitableplan.x;
                    uitableplan.draw.mousedown_y = y - uitableplan.y;
                    uitableplan.draw.mousemove_x = x - uitableplan.x;
                    uitableplan.draw.mousemove_y = y - uitableplan.y;
                }
            }
            else {
                uitableplan.draw.mousedown_x = null;
                uitableplan.draw.mousedown_y = null;

            }
        }
        this.button.onMouseDown(x, y);
        this.numpad.onMouseDown(x, y);

    }
    onMouseUp(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true) && uitableplan.draw.mousedown_x != null) {
                var x = 0;
                var y = 0;
                var width = 0;
                var height = 0;
                if (uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x > 0) {
                    x = uitableplan.draw.mousedown_x + uitableplan.x;
                    width = uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x;
                }
                else {
                    x = uitableplan.draw.mousemove_x + uitableplan.x;
                    width = uitableplan.draw.mousedown_x - uitableplan.draw.mousemove_x;
                }
                if (uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y > 0) {
                    y = uitableplan.draw.mousedown_y + uitableplan.y;
                    height = uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y;
                }
                else {
                    y = uitableplan.draw.mousemove_y + uitableplan.y;
                    height = uitableplan.draw.mousedown_y - uitableplan.draw.mousemove_y;
                }
                if (uitableplan.rect) {
                    uitableplan.rects.push({
                        x: x, y: y, width: width, height: height
                    });
                }
                else if (uitableplan.circle) {
                    uitableplan.circles.push({
                        x: x, y: y, width: width, height: height
                    })
                }
                uitableplan.draw.mousedown_x = null;
                uitableplan.draw.mousedown_y = null;
                uitableplan.draw.mousemove_x = null;
                uitableplan.draw.mousemove_y = null;
                this.update();
            }
        }
        this.button.onMouseUp(x, y);
        this.numpad.onMouseUp(x, y);
        this.dragndrop.onMouseUp(x, y);
    }
    onMouseMove(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.select) {
                this.dragndrop.onMouseMove(x, y);
            }
            else if (uitableplan.rect || uitableplan.circle) {
                $(this.canvas).css('cursor', 'crosshair');
            }
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                uitableplan.draw.mousemove_x = x - uitableplan.x;
                uitableplan.draw.mousemove_y = y - uitableplan.y;
                if (x < uitableplan.x) {
                    uitableplan.draw.mousemove_x = 0;
                }
                else if (x > uitableplan.x + uitableplan.width - 225) {
                    uitableplan.draw.mousemove_x = uitableplan.width - 225;
                }
                if (y < uitableplan.y) {
                    uitableplan.draw.mousemove_y = 0;
                }
                else if (y > uitableplan.y + uitableplan.height - 70) {
                    uitableplan.draw.mousemove_y = uitableplan.height - 70;
                }
                triggerRepaint();
            }
            else {
                uitableplan.draw.mousemove_x = null;
                uitableplan.draw.mousemove_y = null;
            }
        }
        this.button.onMouseMove(x, y);
        this.numpad.onMouseMove(x, y);


    }
    find(name) {
        return;
    }
}