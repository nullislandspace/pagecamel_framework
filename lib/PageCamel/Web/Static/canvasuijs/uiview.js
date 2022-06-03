var __canvasuijs = new Object();
__canvasuijs.types = new Object();
__canvasuijs.registerTypes = function(typename, classname);



class UIView {
    constructor(canvas) {
        this.is_active = false;
        this.canvas = '#' + canvas;
        var selectDialogueLink = $('<a href="">Select files</a>');
        var fileSelector = $('<input type="file">');

        selectDialogueLink.on('click', function () {
            fileSelector.click();
            return false;
        });
        $(this.canvas).html(selectDialogueLink);
        this.ctx = document.getElementById(canvas).getContext('2d');
        this.button = new UIButton(this.canvas);
        this.line = new UILine(this.canvas);
        this.text = new UIText(this.canvas);
        this.numpad = new UINumpad(this.canvas);
        this.list = new UIList(this.canvas);
        this.arrowbutton = new UIArrowButton(this.canvas);
        this.textbox = new UITextBox(this.canvas);
        this.scrolllist = new UIScrollList(this.canvas);
        this.dragndrop = new UIDragNDrop(this.canvas);
        this.tableplan = new UITablePlan(this.canvas);
        this.buttonrow = new UIButtonRow(this.canvas);
        this.dialog = new UIDialog(this.canvas);
        this.colorpalet = new UIColorPalet(this.canvas);
        this.image = new UIImage(this.canvas);
        this.checkbox = new UICheckBox(this.canvas);
        this.textinput = new UITextInput(this.canvas);
        this.ui_types = [
            { type: 'TextBox', object: this.textbox },
            { type: 'Button', object: this.button },
            { type: 'Line', object: this.line },
            { type: 'Text', object: this.text },
            { type: 'Numpad', object: this.numpad },
            { type: 'List', object: this.list },
            { type: 'ArrowButton', object: this.arrowbutton },
            { type: 'ScrollList', object: this.scrolllist },
            { type: 'DragNDrop', object: this.dragndrop },
            { type: 'TablePlan', object: this.tableplan },
            { type: 'ButtonRow', object: this.buttonrow },
            { type: 'ColorPalet', object: this.colorpalet },
            { type: 'Image', object: this.image },
            { type: 'Checkbox', object: this.checkbox },
            { type: 'TextInput', object: this.textinput },
            { type: 'Dialog', object: this.dialog }, // Dialog should always be last to render
        ];//Change when adding new UI Type

        this.onClick = this.onClick.bind(this);
        this.onMouseUp = this.onMouseUp.bind(this);
        this.onMouseDown = this.onMouseDown.bind(this);
        this.onMouseMove = this.onMouseMove.bind(this);
        this.onKeyDown = this.onKeyDown.bind(this);
        this.onKeyUp = this.onKeyUp.bind(this);
        this.fileHandler = this.fileHandler.bind(this);

        $(this.canvas).on('mousedown', this.onMouseDown);
        window.addEventListener('keydown', this.onKeyDown, false);
        window.addEventListener('keyup', this.onKeyUp, false);
        $(this.canvas).on('mouseup', this.onMouseUp);
        $(this.canvas).on('click', this.onClick);
        $(this.canvas).on('mouseleave', this.onMouseUp);
        $(this.canvas).on('mouseleave', this.onClick);
        $(this.canvas).on('mousemove', this.onMouseMove);
        $("#upload").on("change", this.fileHandler);
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
                if (ui_type.object.onClick != undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.onClick(x, y);
                    }
                }
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
                if (ui_type.object.onMouseUp != undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.onMouseUp(x, y);
                    }
                }
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
                if (ui_type.object.onMouseDown != undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.onMouseDown(x, y);
                    }
                }
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
                if (ui_type.object.onMouseMove != undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.onMouseMove(x, y);
                    }
                }
            }
        } else {
            return;
        }
    }
    onKeyDown(e) {
        if (this.is_active == true) {
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onKeyDown !== undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.onKeyDown(e);
                    }
                }
            }
        } else {
            return;
        }
    }
    fileHandler() {
        var input = document.querySelector('#upload');
        if (this.is_active == true) {
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.fileHandler !== undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.fileHandler(input);
                    }
                }
            }
        } else {
            return;
        }
    }
    onKeyUp(e) {
        if (this.is_active == true) {
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onKeyUp !== undefined) {
                    if (this.dialog.dialogs.length == 0 || ui_type.type == 'Dialog') {
                        ui_type.object.onKeyUp(e);
                    }
                }
            }
        } else {
            return;
        }
    }
}
