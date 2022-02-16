class UIList {
    constructor() {
        this.lists = []
        this.button = new UIButton();
    }
    add(options) {
        options.setList = (params) => {
            options.articles = params;
        }
        this.lists.push(options);
        return options
    }
    getArticlePosition(max_x_buttons, max_y_buttons, article_index){
        var max_buttons = max_x_buttons * max_y_buttons;//max buttons per page
        var x = (article_index % max_x_buttons)
        var y = Math.round((article_index / max_x_buttons) - 0.49);
        return [x, y];   
    }
    
    render(ctx) {
        this.button.clear();
        for (var i in this.lists){
            var list = this.lists[i];
            for (var j in list.articles){
                var button_x;
                var button_y;
                var article = list.articles[j];
                var button = {...article, ...list.elementOptions};
                var max_y_buttons = Math.round(list.height / (button.height  + button.gap) - 0.49);
                var max_x_buttons = Math.round((list.width - list.scrollbarwidth) / (button.width + button.gap) - 0.49);
                var [x, y] = this.getArticlePosition(max_x_buttons, max_y_buttons, j);
                if (y < max_y_buttons){
                    button_x = list.x + x * (button.width + button.gap);
                    button_y = list.y + y * (button.height + button.gap);
                    button.x = button_x;
                    button.y = button_y;
                    this.button.add(button);
                }
                else{
                }
            }
            this.button.render(ctx);
        }
        /*for (let i in this.buttons) {
            let button = this.buttons[i];
        }*/
    }
    onClick(x, y) {
        for (let i in this.buttons) {
            this.buttons.onClick(x ,y);
        }
    }
    onHover(x, y) {
        for (let i in this.buttons) {
            this.buttons.onHover(x ,y);
        }
    }
    onMouseDown(x, y) {
        for (let i in this.buttons) {
            this.buttons.onMouseDown(x ,y);
        }
    }
    onMouseUp(x, y) {
        for (let i in this.buttons) {
            this.buttons.onMouseUp(x ,y);
        }
    }
    find(name) {
        console.log('searching');
        for(var i in this.lists){
            var list = this.lists[i];
            if (list.name == name){
                return list;
            } 
        }
    }
    
}