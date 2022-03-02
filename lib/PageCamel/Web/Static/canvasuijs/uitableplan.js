class UITablePlan {
    constructor() {
        this.uitableplans = [];
        this.dragndrop = new UIDragNDrop();
        this.button = new UIButton();
    }
    add(options) {
        options.editable = false;
        this.uitableplans.push(options);

        return options;
    }
    render(ctx) {
        for (var i in this.uitableplans) {
            var uitableplan = this.uitableplans[i];
            ctx.fillStyle = uitableplan.background[0];
            ctx.strokeStyle = uitableplan.border;
            ctx.fillRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
            ctx.strokeRect(uitableplan.x, uitableplan.y, uitableplan.width, uitableplan.height);
        }
        this.button.render()
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
}