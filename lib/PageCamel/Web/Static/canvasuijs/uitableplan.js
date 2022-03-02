class UITablePlan {
    constructor() {
        this.uitableplans = [];
        this.dragndrop = new UIDragNDrop();
        this.button = new UIButton();
    }
    add(options) {
        options.editable = false;
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
        this.uitableplans.push(options);
        this.update();
        return options;
    }
    update() {
        this.button.clear();
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            if (uitableplan.editable == false) {
                this.button.add({
                    displaytext: '🖉 Bearbeiten',
                    background: ['#4fbcff', '#009dff'], foreground: '#000000', border: '#4fbcff', border_width: 3, grd_type: 'vertical',
                    x: uitableplan.x + 20, y: uitableplan.y + uitableplan.height - 60, width: 150, height: 45, border_radius: 20, font_size: 18, hover_border: '#009dff',
                    callback: uitableplan.edit
                });
            }
            else {
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
            ctx.strokeStyle = uitableplan.border;
            ctx.lineWidth = button.border_width;
            ctx.fillRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            ctx.strokeRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            ctx.fillStyle = '#A9A9A9';
            ctx.fillRect(uitableplan.x + uitableplan.border_width / 2, uitableplan.y + uitableplan.height - 70, uitableplan.width - uitableplan.border_width, 70 - uitableplan.border_width);
        }
        this.button.render(ctx);
    }
    onClick(x, y) {
        this.button.onClick(x, y);
    }
    onMouseDown(x, y) {
        this.button.onMouseDown(x, y);
    }
    onMouseUp(x, y) {
        this.button.onMouseUp(x, y);
    }
    onMouseMove(x, y) {
        this.button.onMouseMove(x, y);
    }
    find(name) {
        this.button.find(name);
    }
}