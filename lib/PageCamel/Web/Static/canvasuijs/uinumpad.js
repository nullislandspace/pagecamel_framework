class UINumpad {
    constructor() {
        this.button = new UIButton();
        this.numpads = [];
    }
    
    new(options) {
        this.numpads.push(options);
        //addButtonGroup(x, y, width, height, gap, buttontexts, keyvalues, textcolor, buttoncolor, callback, callbackData, roundCorner) {
        var button_options =  options;
        button_options.type = 'Button';

        var keyvalues = [['+/-', 'ZWS', 'BS'],['7', '8', '9'],['4', '5', '6'],['1', '2', '3'],['x', '0', ',']]
        if(!options.show_keys.x) {

        }
        if(!options.show_keys.ZWS) {

        }

        var button_height = options.height / keyvalues.length - options.gap; //change
        var button_width = options.width / keyvalues[0].length - options.gap;
        button_options.height = button_height;
        button_options.width = button_width;
        for (var buttons_y = 0; buttons_y < keyvalues.length; buttons_y++) {
            var position_y = options.y + (button_height + options.gap) * buttons_y;
            for (var buttons_x = 0; buttons_x < keyvalues[0].length; buttons_x++) {
                if (keyvalues[buttons_y][buttons_x] != null) {
                    var position_x = options.x + (button_width + options.gap) * buttons_x;
                    var each_button_options =  Object.create(button_options);
                    each_button_options.callbackData.value = keyvalues[buttons_y][buttons_x];
                    each_button_options.x = position_x;
                    each_button_options.y = position_y;
                    each_button_options.displaytext = keyvalues[buttons_y][buttons_x];
                    console.log(each_button_options);
                    this.button.new(each_button_options);
                }
            }
        }
        return options;
    }
    
    render(ctx) {
        this.button.render(ctx);
    }

    onClick(x, y) {
        this.button.onClick(x, y);
    }
}