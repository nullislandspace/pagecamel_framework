import { CXButton } from "./cxbutton.js";
export class CXArrowButton extends CXButton {
    protected _arrow_color: string;
    protected _arrow_width: number;
    protected _arrow_height: number;
    protected _arrow_direction: string;
    protected _arrow_width_pixel: number;
    protected _arrow_height_pixel: number;
    /**
     * @param {CanvasRenderingContext2D} ctx the context to draw on
     * @param {number} x the x coordinate of the button
     * @param {number} y the y coordinate of the button
     * @param {number} width the width of the button
     * @param {number} height the height of the button
     * @param {boolean} is_relative if true, the x, y, width and height are relative to the parent and between 0 and 1
     * @param {boolean} redraw if true, the button can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean, redraw: boolean) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._arrow_color = "black";
        this._arrow_width = 0.8;
        this._arrow_height = 0.8;
        this._arrow_direction = "right";

        this._arrow_width_pixel = 0;
        this._arrow_height_pixel = 0;
    }
    /**
     * @description draws the arrow
     * @protected
     */
    protected _drawArrow(): void {
        this._ctx.fillStyle = this._arrow_color;
        this._ctx.beginPath();
        if (this._arrow_direction == "right") {
            // draw an arrow pointing to the right
            this._ctx.moveTo(this.xpixel + this.widthpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 - this._arrow_height_pixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel - this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 + this._arrow_height_pixel / 2);
        }
        else if (this._arrow_direction == "left") {
            // draw an arrow pointing to the left
            this._ctx.moveTo(this.xpixel, this.ypixel + this.heightpixel / 2);
            this._ctx.lineTo(this.xpixel + this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 - this._arrow_height_pixel / 2);
            this._ctx.lineTo(this.xpixel + this._arrow_width_pixel, this.ypixel + this.heightpixel / 2 + this._arrow_height_pixel / 2);
        }
        else if (this._arrow_direction == "up") {
            // draw an arrow pointing to the top
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this._arrow_width_pixel / 2, this.ypixel + this._arrow_height_pixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this._arrow_width_pixel / 2, this.ypixel + this._arrow_height_pixel);
        }
        else if (this._arrow_direction == "down") {
            // draw an arrow pointing to the bottom
            this._ctx.moveTo(this.xpixel + this.widthpixel / 2, this.ypixel + this.heightpixel - this.heightpixel / 2 + this._arrow_height_pixel / 2);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 - this._arrow_width_pixel / 2, this.ypixel + this.heightpixel - this._arrow_height_pixel);
            this._ctx.lineTo(this.xpixel + this.widthpixel / 2 + this._arrow_width_pixel / 2, this.ypixel + this.heightpixel - this._arrow_height_pixel);
        }
        this._ctx.closePath();
        this._ctx.fill();
    }
    /**
     * @description draws the arrow and button
     * @protected
     */
    protected _draw(): void {
        super._draw();
        this._arrow_height_pixel = this._calcRelYToPixel(this._arrow_height, this._heightpixel);
        this._arrow_width_pixel = this._calcRelXToPixel(this._arrow_width, this._widthpixel);

        this._drawArrow();
    }
    /**
     * @returns {string} the arrow color
     */
    get arrow_color(): string {
        return this._arrow_color;
    }
    /** 
     * @param {string} color the arrow color
     */
    set arrow_color(color: string) {
        this._arrow_color = color;
    }
    /**
     * @returns {number} the arrow width in relative units
     */
    get arrow_width(): number {
        return this._arrow_width;
    }
    /**
     * @param {number} width the arrow width in relative units
     */
    set arrow_width(width: number) {
        this._arrow_width = width;
    }
    /**
     * @returns {number} the arrow height in relative units
     */
    get arrow_height(): number {
        return this._arrow_height;
    }
    /**
     * @param {number} height the arrow height in relative units
     */
    set arrow_height(height: number) {
        this._arrow_height = height;
    }
    /**
     * @returns {string} the arrow direction
     * @description possible values: "right", "left", "up", "down"
     */
    get arrow_direction(): string {
        return this._arrow_direction;
    }
    /**
     * @param {string} direction the arrow direction
     * @description possible values: "right", "left", "up", "down"
     */
    set arrow_direction(direction: string) {
        this._arrow_direction = direction;
    }
}