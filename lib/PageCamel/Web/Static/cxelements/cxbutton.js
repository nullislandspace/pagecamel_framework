class CXButton extends CXTextBox {
    constructor(ctx, x, y, width, height, is_relative = true) {
        super(ctx, x, y, width, height, is_relative);

        this.allow_hover = false; // if true, the button will change colors when the mouse is over it         
    }
    _drawButton() {
        this._drawTextBox();
    }
    _draw() {
        this._drawButton();
    }

    mouseInHandler = () => {
        if (this.allow_hover) {
            if (this.hover_frame_color != undefined) {
                this.default_frame_color = this.frame_color;
                this.frame_color = this.hover_frame_color;
            }
            if (this.hover_text_color != undefined) {
                this.default_text_color = this.text_color;
                this.text_color = this.hover_text_color;
            }
            if (this.hover_box_color != undefined) {
                this.default_box_color = this.box_color;
                this.box_color = this.hover_box_color;
            }
            //triggerRepaint();
        }
    }
    mouseOutHandler = () => {
        if (this.allow_hover) {
            if (this.default_frame_color != undefined) {
                this.frame_color = this.default_frame_color;
            }
            if (this.default_text_color != undefined) {
                this.text_color = this.default_text_color;
            }
            if (this.default_box_color != undefined) {
                this.box_color = this.default_box_color;
            }
            //triggerRepaint();
        }
    }
}