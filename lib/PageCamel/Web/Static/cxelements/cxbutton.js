class CXButton extends CXTextBox {
    constructor(ctx, x, y, width, height) {
        super(ctx, x, y, width, height);
        this.default_frame_color = this.frame_color;
        this.default_text_color = this.text_color;
        this.default_box_color = this.box_color;

        this.hover_frame_color = this.frame_color;
        this.hover_text_color = this.text_color;
        this.hover_box_color = this.box_color;

        this.allow_hover = false; // if true, the button will change colors when the mouse is over it         
    }
    _drawButton() {
        this._drawTextBox();
    }
    draw () {
        this._drawButton();
    }
    hoverInHandler = () => {
        if (this.allow_hover) {
            if (this.hover_frame_color != undefined) {
                this.frame_color = this.hover_frame_color;
            }
            if (this.hover_text_color != undefined) {
                this.text_color = this.hover_text_color;
            }
            if (this.hover_box_color != undefined) {
                this.box_color = this.hover_box_color;
            }
            this._drawButton(this.xpos, this.ypos, this.width, this.height);
        }
    }
    hoverOutHandler = () => {
        if (this.allow_hover) {
            this.frame_color = this.default_frame_color;
            this.text_color = this.default_text_color;
            this.box_color = this.default_box_color;
            this._drawButton(this.xpos, this.ypos, this.width, this.height);
        }
    }
}