import { CXDefault } from "./cxdefault.js";
import { CXButton } from "./cxbutton.js";
export class CXButtonGrid extends CXDefault {
    /** @protected */
    protected _buttons_text_block: (string | null | object)[][];
    /** @protected */
    protected _buttons: CXButton[][];
    /** @protected */
    protected _gap: number;
    /** @protected */
    protected _font_size: number;
    /**
     * Maximum number of columns of the given buttons_text_block
     */
    protected _max_number_of_cols: number;
    /**
     * Total number of rows of the given buttons_text_block
     */
    protected _number_of_rows: number;
    protected _current_value: string | null;

    protected _button_attributes: object | null = null;

    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean, redraw: boolean) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._buttons_text_block = [['7', '8', '9'], ['4', '5', '6'], ['1', '2', '3'], ['+/-', '0', ',']];
        this._max_number_of_cols = 3;
        this._number_of_rows = 4;
        this._current_value = null;

        this._buttons = [];
        this._gap = 0.02;

        this._font_size = 0.5;
        this._calcButtonHeigth();
        this._createButtons();

    }

    //calculate the button heigth relative or in pixel
    private _calcButtonHeigth(): number {
        let button_height = 0;
        if (this.is_relative) {
            button_height = (1 - this._gap * (this._number_of_rows - 1)) / this._number_of_rows;
        }
        else {
            button_height = (this.height - this._gap * (this._number_of_rows - 1)) / this._number_of_rows;
        }
        return button_height;
    }

    //calculate the button width relative or in pixel for a given row
    private _calcButtonWidth(rownumber: number): number {
        let button_width = 0;
        //calculate the button_width
        if (this.is_relative) {
            button_width = (1 - this._gap * (this._buttons_text_block[rownumber].length - 1)) / this._buttons_text_block[rownumber].length;
        }
        else {
            button_width = Math.floor((this.width - this._gap * (this._buttons_text_block[rownumber].length - 1)) / this._buttons_text_block[rownumber].length);
        }
        return button_width;
    }

    //create the buttons and add it to the _buttons array
    protected _createButtons(): void {
        this._buttons = [];
        var button_width = 0;
        var button_height = this._calcButtonHeigth();


        let xgap = this._gap;
        let ygap = this._gap;
        //for all columns
        for (var rw = 0; rw < this._number_of_rows; rw++) {
            var row: CXButton[] = [];
            //calculate the button_width
            button_width = this._calcButtonWidth(rw);
            for (var col = 0; col < this._buttons_text_block[rw].length; col++) {
                xgap = this._gap;
                ygap = this._gap;
                if (rw == 0) { ygap = 0; }
                if (col == 0) { xgap = 0; }
                if (this._buttons_text_block[rw][col] != null) {
                    var button = new CXButton(this._ctx, col * (button_width + xgap), rw * (button_height + ygap), button_width, button_height, this._is_relative, true);
                    //default values
                    button.text = <string>this._buttons_text_block[rw][col];
                    button.hover_border_color = '#ffffff';
                    button.gradient = ['#f9a004', '#ff0202'];
                    button.text_color = '#000000';
                    button.border_color = '#ff0000';
                    //set onclick event callback
                    button.onClick = (clickedbutton: CXButton) => this._onClickButtonCallback(clickedbutton);
                    if (this.is_relative) {
                        button.border_radius = 0.1;
                        button.font_size = this._font_size;
                    }
                    else {
                        button.border_radius = Math.ceil(0.1 * button_height);
                        button.font_size = Math.ceil(this._font_size * button_height);
                    }
                    if (typeof this._buttons_text_block[rw][col] != 'string') {
                        //if object overwrite the default values
                        button.attributes = <object>this._buttons_text_block[rw][col];
                    }
                    //overwrite all settings with button attributes settings
                    if (this._button_attributes) {
                        button.attributes = this._button_attributes;
                    }
                    row.push(button);
                }
            }
            this._buttons.push(row);
        }
    }
    /**
     * @description Draws the buttons of the num pad
     * @protected
     */
    protected _drawNumpad(): void {
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                this._buttons[i][j].draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
            }
        }
    }
    /**
     * @protected
     */
    _draw(): void {
        this._drawNumpad();
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    protected _handleEvent(event: Event): boolean {
        let clicked = false;
        let handled = false;
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                if (this._buttons[i][j].checkEvent(event)) {
                    this._buttons[i][j].handleEvent(event);
                    handled = true;
                }
            }
        }

        //run callback if the value has changed
        if (this._has_changed) {
            //Set _has_changed = false after calling the callback-function
            this.onClick(this, this.currentValue);
            this._has_changed = false;
        }
        return handled;
    }

    private _onClickButtonCallback(obj: CXButton): void {
        this._current_value = obj.text;
        this._has_changed = true;
    }

    private _calcMaxColRowLength(): void {
        //Get maximum row length
        let max_row_length = 0;
        let max_col_length = 0;
        for (var row = 0; row < this._buttons_text_block.length; row++) {
            if (this._buttons_text_block[row].length > max_row_length) {
                max_row_length = this._buttons_text_block[row].length;
            }
        }
        this._max_number_of_cols = max_row_length;
        this._number_of_rows = this._buttons_text_block.length;
    }

    /**
     * Callback function to handle click events 
     * 
     * @param val - the value of the clicked numpad item
     * @param object - the object of the numpad
     */
    onClick: (object: this, val: string | null) => void = (): void => {
        console.log("Override this callback function");
    }

    /**
     * Calculates the optimal width to the adjusted height, so that the buttons are squares
     * 
     *@return width - in pixel (absolute) or relative (to the parent object)
     */
    calcOptimalWidth(): number {
        let total_width = 0;

        let col_length = this._buttons_text_block.length;
        let button_width = 0;
        let button_height = this._calcButtonHeigth();
        let width = 0;

        if (this.is_relative) {
            button_width = this._calcRelYToPixel(button_height * this.height);
            width = this._calcPixelXToRel(button_width / this.width);
        }
        else {
            button_width = button_height;
            width = button_width;
        }


        //Calculate total width in relative or pixel
        total_width = this._max_number_of_cols * width + (this._max_number_of_cols - 1) * this._gap;

        //Calculate relative to the current width if is_relative=true
        if (this.is_relative) { total_width = total_width * this.width };





        console.debug("cxnumpad - calcOptimalWidth:" + total_width.toString());
        return total_width;
    }

    /**
     * Calculates the optimal width to the adjusted height, so that the buttons are squares
     * 
     *@return width - in pixel (absolute) or relative (to the parent object)
     */
    calcOptimalHeight(): number {
        let total_heigth = 0;
        this._calcMaxColRowLength();

        let col_length = this._buttons_text_block.length;
        let button_width = this._buttons[0][0].width;
        let button_height = 0;
        let height = 0;


        let calc_row = 0;
        //check all rows and find the minimum button-width
        for (var row = 0; row < this._number_of_rows; row++) {
            //is row-length equal maximum row-length
            if (this._max_number_of_cols == this._buttons[row].length) {
                //search for the minimum button-width
                for (var col = 0; col < this._buttons[row].length; col++) {
                    if (button_width > this._buttons[row][col].width) {
                        button_width = this._buttons[row][col].width;
                    }
                }
            }
        }

        if (this.is_relative) {
            //set relative button_height to button_width in pixel
            button_height = this._calcRelXToPixel(button_width * this.width);
            //calculate back to relative height
            height = this._calcPixelYToRel(button_height / this.height);
        }
        else {
            height = button_width;

        }


        //Calculate total heigth in relative or pixel
        total_heigth = this._number_of_rows * height + (this._number_of_rows - 1) * this._gap;

        //Calculate relative to the current heigth if is_relative=true
        if (this.is_relative) { total_heigth = total_heigth * this.height };





        console.debug("cxnumpad - calcOptimalHeigth:" + total_heigth.toString());
        return total_heigth;
    }

    /**
     * Set square size.
     * FIFO: If width not NULL -> calculate the heigth
     *       If width is NULL and heigth not NULL -> calculate the width
     * @remarks 
     * Use setSquareSize() to calculate the width to the already adjusted height
     * Use setSquareSize(this.width) to calculate the heigth to the already adjusted width
     * 
     * @param width - Width in pixel/relativ or NULL
     * @param height - Heigth in pixel/relativ or NULL   
     */
    setSquareSize(width: number | null = null, heigth: number | null = this.height): void {
        super.setSquareSize(width, heigth);
        this._buttons = [];
        this._createButtons();
    }

    /** 
     * @param {number} value - Font size in either pixels or relative to button size
     * @description Sets the font size of the text in the button
     */
    set font_size(value: number) {
        this._font_size = value;
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                this._buttons[i][j].font_size = value;
            }
        }
    }


    get font_size(): number {
        return this._font_size;
    }
    /**
     * @param {number} value - The gap between buttons in either pixels or relative to button size
     * @description Sets the gap between buttons
     */
    set gap(value: number) {
        this._gap = value;
        this._elements = [];
        this._createButtons();
    }
    get gap(): number {
        return this._gap;
    }

    get buttons_text_block(): (string | null | object)[][] {
        return this._buttons_text_block;
    }

    set buttons_text_block(val: (string | null | object)[][]) {
        this._buttons_text_block = val;
        this._calcMaxColRowLength();
        this._createButtons();
    }

    set width(val: number) {
        this._width = val;
        this._buttons = [];
        this._createButtons();
    }

    get width(): number {
        return this._width;
    }

    set height(val: number) {
        this._height = val;
        this._buttons = [];
        this._createButtons();
    }

    get height(): number {
        return this._height;
    }

    /**
     * returns the value of the last selected item
     */
    get currentValue(): string | null {
        return this._current_value;
    }

    /**
     * set button attributes
     */
    set buttonAttributes(attributes: object | null) {
        this._button_attributes = attributes;
    }
}