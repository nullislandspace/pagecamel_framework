class UIView {
    constructor(canvas) {
        this.is_active = false;
        this.canvas = '#' + canvas;
        this.ctx = document.getElementById(canvas).getContext('2d');

        this.button = new UIButton(this.canvas);
        this.line = new UILine(this.canvas);
        this.text = new UIText(this.canvas);
        this.numpad = new UINumpad(this.canvas);
        this.list = new UIList(this.canvas);
        this.arrowbutton = new UIArrowButton(this.canvas);
        this.textbox = new UITextBox(this.canvas);
        this.paylist = new UIPayList(this.canvas);
        this.dragndrop = new UIDragNDrop(this.canvas);
        this.tableplan = new UITablePlan(this.canvas);
        this.ui_types = [
            { type: 'Button', object: this.button },
            { type: 'Line', object: this.line },
            { type: 'Text', object: this.text },
            { type: 'Numpad', object: this.numpad },
            { type: 'List', object: this.list },
            { type: 'ArrowButton', object: this.arrowbutton },
            { type: 'TextBox', object: this.textbox },
            { type: 'PayList', object: this.paylist },
            { type: 'DragNDrop', object: this.dragndrop },
            { type: 'TablePlan', object: this.tableplan }
        ];//Change when adding new UI Type

        this.onClick = this.onClick.bind(this);
        this.onMouseUp = this.onMouseUp.bind(this);
        this.onMouseDown = this.onMouseDown.bind(this);
        this.onMouseMove = this.onMouseMove.bind(this);

        $(this.canvas).on('mousedown', this.onMouseDown);
        $(this.canvas).on('mouseup', this.onMouseUp);
        $(this.canvas).on('click', this.onClick);
        $(this.canvas).on('mouseleave', this.onMouseUp);
        $(this.canvas).on('mouseleave', this.onClick);
        $(this.canvas).on('mousemove', this.onMouseMove);
        /*this.d_options = {
            background-color: #...
        }*/
    }
    element(name) {
        for (var i in this.ui_types) {
            var obj = this.ui_types[i].object.find(name);
            if (obj != null) {
                return obj;
            }
        }
    }
    addElement(element_type, options) {
        for (var i in this.ui_types) {
            if (this.ui_types[i].type == element_type) {
                options.type = element_type;
                this.ui_types[i].object.add(options);
                return this.ui_types[i].object;
            }
        }
    }

    render() {
        if (this.is_active) {
            for (let i in this.ui_types) {
                this.ui_types[i].object.render(this.ctx);
            }
        }
        else {
            return;
        }
    }
    setActive(state) {
        this.is_active = state;

    }
    onClick(e) {
        if (this.is_active == true) {
            var canvas = $(this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onClick(x, y);
            }
        } else {
            return;
        }
    }
    onMouseUp(e) {
        if (this.is_active == true) {
            var canvas = $(this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onMouseUp(x, y);
            }
        } else {
            return;
        }
    }
    onMouseDown(e) {
        if (this.is_active == true) {
            var canvas = $(this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onMouseDown(x, y);
            }
        } else {
            return;
        }
    }
    onMouseMove(e) {
        if (this.is_active == true) {
            var canvas = $(this.canvas);
            var x = Math.floor((e.pageX - canvas.offset().left));
            var y = Math.floor((e.pageY - canvas.offset().top));
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                ui_type.object.onMouseMove(x, y);
            }
        } else {
            return;
        }
    }
}