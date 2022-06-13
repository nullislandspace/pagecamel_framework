class CanvasUIJs {
    constructor() {
        this.canvas = '';
        this.register = [];
    };
    setCanvas = (canvas) => {
        this.canvas = canvas;
    }
    addType = (typename, classname) => {
        this.register.push({ typename: typename, classname: classname });
    }
    getTypes = () => {
        var ui_types = [];
        for (var type of this.register) {
            var object = new type.classname(this.canvas);
            ui_types.push({ type: type.typename, object: object });
        }
        return ui_types;
    }
}
var canvasuijs = new CanvasUIJs();


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
        this.ui_types = canvasuijs.getTypes();
        this.onClick = this.onClick.bind(this);
        this.onMouseUp = this.onMouseUp.bind(this);
        this.onMouseDown = this.onMouseDown.bind(this);
        this.onMouseMove = this.onMouseMove.bind(this);
        this.onKeyDown = this.onKeyDown.bind(this);
        this.onKeyUp = this.onKeyUp.bind(this);
        this.fileHandler = this.fileHandler.bind(this);

        //keyboard events
        window.addEventListener('keydown', this.onKeyDown, false);
        window.addEventListener('keyup', this.onKeyUp, false);


        //mouse events
        $(this.canvas).on('mousedown', this.onMouseDown);
        $(this.canvas).on('mouseup', this.onMouseUp);
        $(this.canvas).on('click', this.onClick);
        $(this.canvas).on('mouseleave', this.onMouseUp);
        $(this.canvas).on('mouseleave', this.onClick);
        $(this.canvas).on('mousemove', this.onMouseMove);

        //remapping touchevents
        $(this.canvas).on("touchstart", this.onMouseDown);
        $(this.canvas).on("touchmove", this.onMouseMove);
        $(this.canvas).on("touchend", this.onMouseUp);
        $(this.canvas).on("touchcancel", this.onMouseUp);


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
        triggerRepaint();
    }
    getDialogActive() {
        for (var type of this.ui_types) {
            if (type.type == 'Dialog') {
                if (type.object.dialogs.length > 0) {
                    return true;
                }
            }
        }
        return false;
    }
    onClick(e) {
        e.preventDefault();
        if (this.is_active == true) {
            var dialog_active = this.getDialogActive();
            var canvas = $(this.canvas);
            var y;
            var x;
            if (e.type == 'click') {
                x = Math.floor((e.pageX - canvas.offset().left));
                y = Math.floor((e.pageY - canvas.offset().top));
            }
            else if (e.changedTouches !== undefined) {
                x = Math.floor((e.changedTouches[0].pageX - canvas.offset().left));
                y = Math.floor((e.changedTouches[0].pageY - canvas.offset().top));
            }
            else {
                return;
            }
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onClick != undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
                        ui_type.object.onClick(x, y);
                    }
                }
            }
        } else {
            return;
        }
    }
    onMouseUp(e) {
        e.preventDefault();
        if (this.is_active == true) {
            var dialog_active = this.getDialogActive();
            var canvas = $(this.canvas);
            var y;
            var x;
            if (e.type == 'mouseup') {
                x = Math.floor((e.pageX - canvas.offset().left));
                y = Math.floor((e.pageY - canvas.offset().top));
            }
            else if (e.changedTouches !== undefined) {
                x = Math.floor((e.changedTouches[0].pageX - canvas.offset().left));
                y = Math.floor((e.changedTouches[0].pageY - canvas.offset().top));
                this.onClick(e);
            }
            else {
                return;
            }
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onMouseUp != undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
                        ui_type.object.onMouseUp(x, y);
                    }
                }
            }
        } else {
            return;
        }
    }
    onMouseDown(e) {
        e.preventDefault();
        if (this.is_active == true) {
            var dialog_active = this.getDialogActive();
            var canvas = $(this.canvas);
            var y;
            var x;
            if (e.type == 'mousedown') {
                x = Math.floor((e.pageX - canvas.offset().left));
                y = Math.floor((e.pageY - canvas.offset().top));
            }
            else if (e.changedTouches !== undefined) {
                this.onMouseMove(e);
                x = Math.floor((e.changedTouches[0].pageX - canvas.offset().left));
                y = Math.floor((e.changedTouches[0].pageY - canvas.offset().top));
            }
            else {
                return;
            }
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onMouseDown != undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
                        ui_type.object.onMouseDown(x, y);
                    }
                }
            }
        } else {
            return;
        }
    }
    onMouseMove(e) {
        e.preventDefault();
        if (this.is_active == true) {
            var dialog_active = this.getDialogActive();
            var canvas = $(this.canvas);
            var y;
            var x;
            if (e.type == 'mousemove') {
                x = Math.floor((e.pageX - canvas.offset().left));
                y = Math.floor((e.pageY - canvas.offset().top));
            }
            else if (e.changedTouches !== undefined) {
                x = Math.floor((e.changedTouches[0].pageX - canvas.offset().left));
                y = Math.floor((e.changedTouches[0].pageY - canvas.offset().top));
            }
            else {
                return;
            }
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onMouseMove != undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
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
            var dialog_active = this.getDialogActive();
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onKeyDown !== undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
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
            var dialog_active = this.getDialogActive();
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.fileHandler !== undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
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
            var dialog_active = this.getDialogActive();
            for (let i in this.ui_types) {
                let ui_type = this.ui_types[i];
                if (ui_type.object.onKeyUp !== undefined) {
                    if (!dialog_active || ui_type.type == 'Dialog') {
                        ui_type.object.onKeyUp(e);
                    }
                }
            }
        } else {
            return;
        }
    }
}

