class UITablePlan {
    constructor(canvas) {
        this.canvas = canvas;
        this.uitableplans = [];
        this.dragndrop = new UIDragNDrop();
        this.button = new UIButton();
        this.numpad = new UINumpad();
    }
    add(options) {
        options.editable = false;
        options.elements = [];
        options.draw = { mousedown_x: null, mousedown_y: null, mousemove_x: null, mousemove_y: null, mouseup_x: null, mouseup_y: null };
        options.redoable = [];
        options.undoable = [];
        options.rects = [];
        options.ellipses = [];
        options.edit = () => {
            options.editable = true;
            this.update();
        }
        options.save = () => {
            options.editable = false;
            this.update();
        }
        options.cancel = () => {
            options.editable = false;
            this.update();
        }
        options.drawCircle = () => {
            $(this.canvas).css('cursor', 'crosshair');
            options.circle = true;
            options.rect = false;
        }
        options.drawRect = () => {
            $(this.canvas).css('cursor', 'crosshair');
            options.rect = true;
            options.circle = false;
        }
        options.drawRect
        this.uitableplans.push(options);
        this.update();
        return options;
    }
    update() {
        this.button.clear();
        this.numpad.clear();
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
            }
        }
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
                ctx.fillRect(uitableplan.draw.mousedown_x + uitableplan.x, uitableplan.draw.mousedown_y + uitableplan.y,
                    uitableplan.draw.mousemove_x - uitableplan.draw.mousedown_x, uitableplan.draw.mousemove_y - uitableplan.draw.mousedown_y);
            }
        }
        this.button.render(ctx);
        this.numpad.render(ctx);
    }
    onClick(x, y) {
        this.button.onClick(x, y);
        this.numpad.onClick(x, y);

    }
    onMouseDown(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                uitableplan.draw.mousedown_x = x - uitableplan.x;
                uitableplan.draw.mousedown_y = y - uitableplan.y;
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
        }
    }
    onMouseMove(x, y) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.editable == true && (uitableplan.circle == true || uitableplan.rect == true)) {
                uitableplan.draw.mousemove_x = x - uitableplan.x;
                uitableplan.draw.mousemove_y = y - uitableplan.y;
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
        this.button.find(name);
        this.numpad.find(name);
    }
}