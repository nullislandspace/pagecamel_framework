class CXFrame {
    constructor(ctx){
        this.ctx = ctx;
        this.frame_color = "black";
        this.xpos = 0;
        this.ypos = 0;
        this.width = 0;
        this.height = 0;
    }
    drawFrame(x, y, width, height) {
        this.ctx.strokeStyle = this.frame_color;
        this.ctx.strokeRect(x, y, width, height);
        this._setOwnPosition(x, y, width, height);
    }
    
    _setOwnPosition(x, y, width, height) {
        this.xpos = x;
        this.ypos = y;
        this.width = width;
        this.height = height;
    }
    checkClick(x, y) {
        // check if mouse click is inside the frame
        if(x >= this.xpos && x <= this.xpos + this.width && y >= this.ypos && y <= this.ypos + this.height) {
            console.log("click inside frame");
            this.clickHandler();
        }
    }
    clickHandler (){
        // override this function in child classes to handle click events
    }
    

}