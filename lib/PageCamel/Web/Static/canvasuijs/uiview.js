class UIView {
    constructor(canvas) {
        //this.d_options = default_options;
        this.ui_elements = [];
        this.is_active = false;
        this.canvas = canvas;
        this.ctx = document.getElementById(this.canvas).getContext('2d');

        this.button = new UIButton();
        this.line = new UILine();
        this.text = new UIText();
        this.numpad = new UINumpad();
        this.ui_types = [{ type: 'Button', object: this.button },
                         { type: 'Line', object: this.line },
                         { type: 'Text', object: this.text },
                         { type: 'Numpad', object: this.numpad}
                                                           ]//Change when adding new UI Type

        this.onClick = this.onClick.bind(this);
        $('#' + this.canvas).on('click', this.onClick);
        /*this.d_options = {
            background-color: #...
        }*/
    }
    addElement(element_type, options) {
        for (let i in this.ui_types) {
            if (this.ui_types[i].type == element_type) {
                options.type = element_type;
                this.ui_types[i].object.new(options);
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
            var canvas = $('#' + this.canvas);
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
}