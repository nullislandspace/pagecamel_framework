class UIView {
    constructor(default_options) {
        this.d_options = default_options;
        this.ui_elements = []
        this.is_active = false;

        this.button = new UIButton();
        this.ui_types = [{ type: 'Button', object: this.button }]//Change when adding new UI Type
        /*this.d_options = {
            background-color: #...
        }*/
    }
    addElement(name, element_type, options) {
        for (let i in this.ui_types) {
            if (this.ui_types[i].type == element_type) {
                this.ui_types[i].object.new(name, options)
            }
        }
    }
    render(ctx) {
        if (this.is_active) {
            for (let i in this.ui_types) {
                this.ui_types[i].object.render(ctx);
            }
        }
        else {
            return
        }
    }
    setActive(state) {
        this.is_active = state;

    }
}