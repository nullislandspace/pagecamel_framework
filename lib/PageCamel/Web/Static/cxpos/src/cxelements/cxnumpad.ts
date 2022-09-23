import { CXDefault } from "./cxdefault.js";
import { CXButton } from "./cxbutton.js";
export class CXNumPad extends CXDefault {
    /** @protected */
    protected _buttons_text_block: (string|null)[][];
    /** @protected */
    protected _buttons: CXButton[][];
    /** @protected */
    protected _gap: number;
    /** @protected */
    protected _font_size: number;
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

        this._buttons = [];
        this._gap = 0.02;
        
        this._font_size = 0.5;
        this._createButtons();
        
    }

    protected _createButtons(): void{
        this._buttons =[]; 
        var button_width = 0;
        var button_height = 0;
        if (this.is_relative){ 
            button_height = (1 - this._gap * (this._buttons_text_block.length-1)) / this._buttons_text_block.length;
        }
        else{
            button_height = (this.height - this._gap * (this._buttons_text_block.length-1)) / this._buttons_text_block.length;
        } 

        let xgap = this._gap;
        let ygap = this._gap;
        for (var rw = 0; rw < this._buttons_text_block.length; rw++) {
            var row: CXButton[] = [];
            if (this.is_relative){
                button_width = (1 - this._gap * (this._buttons_text_block[rw].length-1))/ this._buttons_text_block[rw].length;
            } 
            else{ 
                button_width = (this.width - this._gap * (this._buttons_text_block[rw].length-1))/ this._buttons_text_block[rw].length;
            } 
            for (var col = 0; col < this._buttons_text_block[rw].length; col++) {
                xgap = this._gap;
                ygap = this._gap;
                if (rw==0){ygap=0;} 
                if (col==0 ){xgap=0;} 
                if (this._buttons_text_block[rw][col] != null){ 
                    var button = new CXButton(this._ctx, col * (button_width + xgap), rw * (button_height + ygap), button_width, button_height, this._is_relative, true);
                    button.text = <string>this._buttons_text_block[rw][col];
                    button.hover_border_color = '#ffffff';
                    button.gradient = ['#f9a004', '#ff0202'];
                    button.text_color = '#000000';
                    button.border_color = '#ff0000';
                    button.font_size = this._font_size;
                    button.border_radius = 0.1;
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
    protected _drawNumpad() : void {
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                this._buttons[i][j].draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
            }
        }
    }
    /**
     * @protected
     */
    _draw() {
        this._drawNumpad();
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    protected _handleEvent(event : Event) : boolean {
        for (var i = 0; i < this._buttons.length; i++) {
            for (var j = 0; j < this._buttons[i].length; j++) {
                if (this._buttons[i][j].checkEvent(event)) {
                    this._buttons[i][j].handleEvent(event);
                }
            }
        }
        return this._has_changed;
    }

    /**
     * Calculates the optimal width to the adjusted height, so that the buttons are squares
     * 
     *@return width - in pixel (absolute) or relative (to the parent object)
     */
    calcOptimalWidth(): number{
        let total_width = 0;
        
            let col_length = this._buttons_text_block.length;
            let max_row_length = 0;
            let button_width = 0;
            let button_height = 0;
            let x_gap = 0;
            let width = 0;
            //Get maximum row length
            for (var row = 0; row < this._buttons_text_block.length; row++) {
                if (this._buttons_text_block[row].length > max_row_length){
                    max_row_length = this._buttons_text_block[row].length;
                } 
            }
            if (this.is_relative){
                //Calculate button_height
                button_height = (1 - this._gap * (this._buttons_text_block.length-1)) / this._buttons_text_block.length; 
                button_width = this._calcRelYToPixel(button_height*this.height);
                x_gap = this._gap;
                width = this._calcPixelXToRel(button_width/this.width);
            } 
            else{
                button_height = (this.height - this._gap * (this._buttons_text_block.length-1)) / this._buttons_text_block.length; 
                button_width = button_height;
                x_gap = this._gap;
                width = button_width;
            } 
            
            
            //Calculate total width in relative or pixel
            total_width = max_row_length*width+(max_row_length-1)*this._gap;

            //Calculate relative to the current width if is_relative=true
            if (this.is_relative){ total_width = total_width*this.width};

            

                
        
        console.log("cxnumpad - calcOptimalWidth:" + total_width.toString());
        return total_width;
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
    get font_size() : number {
        return this._font_size;
    }
    /**
     * @param {number} value - The gap between buttons in either pixels or relative to button size
     * @description Sets the gap between buttons
     */
    set gap(value: number) {
        this._gap = value;
        this._elements =[];
        this._createButtons(); 
    }
    get gap() : number {
        return this._gap;
    }

    get buttons_text_block() :(string|null)[][]  {
        return this._buttons_text_block;
    } 

    set buttons_text_block(val: (string|null)[][])  {
        this._buttons_text_block=val;
        this._createButtons();
    } 

    /*draw(px: number = 0, py: number = 0, pwidth: number = this._ctx.canvas.width, pheight: number = this._ctx.canvas.height): void {
        super.draw(px,py,pwidth,pheight);
    } */
}