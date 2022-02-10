class UIList {
    constructor() {
        this.lists = []
    }
    add(options) {
        options.setList = (params) => {
            console.log(params)
        }
        this.lists.push(options);
        return options
    }

    render(ctx) {
        for (let i in this.buttons) {
            let button = this.buttons[i];
        }
    }
    onClick(x, y) {
        for (let i in this.buttons) {
        }
    }
    onHover(x, y) {
        return;
    }
    onMouseDown(x, y) {
        return;
    }
    onMouseUp(x, y) {
        return;
    }
    find(name) {
        console.log('searching');
        for(var i in this.lists){
            var list = this.lists[i];
            if (list.name == name){
                console.log('found');
                return list;
            } 
        }
    }
}