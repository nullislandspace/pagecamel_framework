class UINumpad {
    constructor() {
        this.button = new UIButton();
        this.numpads = []
    }
    new(options) {
        this.numpads.push(options);
        //addButtonGroup(x, y, width, height, gap, buttontexts, keyvalues, textcolor, buttoncolor, callback, callbackData, roundCorner) {
        let button_options =  options;
        let keyvalues = [['+/-', 'ZWS', 'BS'],['7', '8', '9'],['4', '5', '6'],['1', '2', '3'],['x', '0', ',']]
        if(options.show_keys.x){

        }
        if(options.show_keys.ZWS){

        }

        let button_height = height / keyvalues.length - gap;
        let button_width = width / keyvalues[0].length - gap;
        for (let buttons_y = 0; buttons_y < keyvalues.length; buttons_y++) {
            let position_y = y + (button_height + gap) * buttons_y;
            for (let buttons_x = 0; buttons_x < keyvalues[0].length; buttons_x++) {
                if (keyvalues[buttons_y][buttons_x] != null) {
                    let position_x = x + (button_width + gap) * buttons_x;
                    button_options =  options;
                    button_options.callbackData.value = keyvalues[buttons_y][buttons_x];
                    button_options.x = position_x
                    button_options.y = position_y
                    button_options.height = button_height
                    button_options.width = button_width
                    this.button.new(button_options);
                }
            }
        }
        return options
    }
    render(ctx) {
        for (let i in this.numpads) {
            let numpad = this.numpads[i];

        }
    }
    onClick(x, y) {
        return
    }
}