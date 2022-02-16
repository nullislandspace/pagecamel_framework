class UIList {
    constructor() {
        this.lists = []
        this.button = new UIButton();
    }
    add(options) {
        options.setList = (params) => {
            options.articles = params;
            options.scrollPosition = 0;
            this.createList();
        }
        options.decreaseScrollPosition = (params) => {
            console.log('decrease')
            options.scrollPosition -= 1;
            this.createList();
        }
        options.increaseScrollPosition = (params) => {
            console.log('increase')
            options.scrollPosition += 1;
            this.createList();
        }
        this.lists.push(options);
        return options
    }
    createList() {
        this.button.clear(); //needs to be changed
        for (var i in this.lists) {
            var list = this.lists[i];
            var max_y_buttons = Math.round(list.height / (list.elementOptions.height + list.elementOptions.gap) - 0.49);
            var max_x_buttons = Math.round((list.width - list.scrollbarwidth) / (list.elementOptions.width + list.elementOptions.gap) - 0.49);
            for (var j in list.articles) {
                var button_x;
                var button_y;
                var article = list.articles[j];
                var button = { ...article, ...list.elementOptions };//elementOptions = Button Options
                var max_buttons = max_x_buttons * max_y_buttons;//max buttons per page
                var article_index = j - max_buttons * list.scrollPosition;
                var [x, y] = this.getArticlePosition(max_x_buttons, article_index);
                if (y < max_y_buttons && y >= 0) { //Check if button is on this page
                    button_x = list.x + x * (button.width + button.gap);
                    button_y = list.y + y * (button.height + button.gap);
                    button.x = button_x;
                    button.y = button_y;
                    this.button.add(button);
                }
            }

        }
        if (max_buttons * (list.scrollPosition + 1) < list.articles.length) {
            this.button.add({
                background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                x: list.x + list.width - list.scrollbarwidth, y: list.y + list.height - list.scrollbarwidth, width: list.scrollbarwidth, 
                height: list.scrollbarwidth, border_radius: 0, hover_border: '#000000',
                callback: list.increaseScrollPosition
            });
        }
        if (list.scrollPosition != 0) {

            this.button.add({
                background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
                x: list.x + list.width - list.scrollbarwidth, y: list.y, width: list.scrollbarwidth, 
                height: list.scrollbarwidth, border_radius: 0, hover_border: '#000000',
                callback: list.decreaseScrollPosition
            });
        }

    }
    getArticlePosition(max_x_buttons, article_index) {

        var x = (article_index % max_x_buttons)
        var y = Math.round((article_index / max_x_buttons) - 0.49);
        return [x, y];
    }

    render(ctx) {
        this.button.render(ctx);
    }

    onClick(x, y) {
        this.button.onClick(x, y);
    }
    onHover(x, y) {
        this.button.onHover(x, y)
    }
    onMouseDown(x, y) {
        this.button.onMouseDown(x, y)
    }
    onMouseUp(x, y) {
        this.button.onMouseUp(x, y)
    }
    find(name) {
        for (var i in this.lists) {
            var list = this.lists[i];
            if (list.name == name) {
                return list;
            }
        }
    }

}