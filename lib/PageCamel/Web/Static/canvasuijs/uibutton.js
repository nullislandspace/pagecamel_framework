class UIButton {
    constructor (){
        this.buttons = []
    }
    new (name, options) {
        var button = {
            startx: options.x,
            starty: options.y,
            endx: options.x + options.width,
            endy: options.y + options.height,
            displaytext: name,
            style: options.style,
            type: 'Button',
            callback: options.callback.function,
            callbackData: {key : options.callback.key, value : options.callback.value}
        }
        this.buttons.push(button);
        return button
    }
    render (ctx) {
        for(let i in this.buttons){
            console.log(i)
        }
    }
}