class UILine {
    constructor() {
        this.lines = [];
    }
    add(options) {
        this.lines.push(options);
        return options;
    }
    render(ctx) {
        for(let i in this.lines) {
            let line = this.lines[i];
            ctx.strokeStyle = line.background;
            ctx.lineWidth = line.thickness;
            let x = line.x;
            let y = line.y;
            let endx = x + line.width;
            let endy = y + line.height
            ctx.beginPath();
            ctx.moveTo(x, y);
            ctx.lineTo(endx, endy);
            ctx.stroke();
        }
    }
    onClick(x,y){
        return;
    }
    onHover(x,y){
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
    find(name){
        return;
    }
}