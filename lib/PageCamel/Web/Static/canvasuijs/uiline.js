class UILine {
    constructor() {
        this.lines = []
    }
    new(name, options) {
        var line = {
            startx: options.x,
            starty: options.y,
            width: options.width,
            height: options.height,
            type: 'Line',
            background: options.background_color,
            thickness: options.thickness
        }
        this.lines.push(line);
        return line
    }
    render(ctx) {
        for(let i in this.lines) {
            let line = this.lines[i];
            ctx.strokeStyle = line.background;
            ctx.lineWidth = line.thickness;
            let startx = line.startx;
            let starty = line.starty;
            let endx = startx + line.width;
            let endy = starty + line.height
            ctx.beginPath();
            ctx.moveTo(startx, starty);
            ctx.lineTo(endx, endy);
            ctx.stroke();
        }
    }
    onClick(x,y){
        return
    }
}