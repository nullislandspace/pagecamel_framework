import { CXFrame } from "./cxframe.js";
/**
 * @extends CXFrame 
 */
export class CXBox extends CXFrame {
    /** @protected */
    protected _background_color: string;
    /** @protected */
    protected _gradient: string[];
    /** @protected */
    protected _first_gradient_color: string;
 
    /**
     * @constructor  
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
    */
     constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._background_color = "green";
        this._gradient = [];
        this._first_gradient_color = "";
        this._name = "CXBox";
    }
    /**
     * @description Draws the box
     * @protected
     */
     protected _drawBox(): void {
        this._ctx.fillStyle = this._background_color;
        if (this._gradient.length > 0) {
            var grd = this._ctx.createLinearGradient(this.xpixel, this.ypixel, this.xpixel, this.ypixel + this.heightpixel);
            var step_size = 1 / (this._gradient.length - 1);
            for (var i = 0; i < this._gradient.length; i++) {
                grd.addColorStop(i * step_size, this._gradient[i]);
            }
            this._ctx.fillStyle = grd;
        }
        super._draw();
        if (this._radius > 0) {
            //fill rounded rectangle
            this._ctx.fill();
        }
        else {
            //fill rectangle
            var x = this.xpixel + Math.ceil(this._border_width_pixel / 2);
            var y = this.ypixel + Math.ceil(this._border_width_pixel / 2);
            var width = this.widthpixel - this._border_width_pixel;
            var height = this.heightpixel - this._border_width_pixel;
            this._ctx.fillRect(x, y, width, height);
        }
    }
    /**
     * @description Draws everything
     * @protected
     */
    protected _draw(): void {
        this._drawBox();
    }
    /**
     * @param {string} color - Color of the box
     */
     set background_color(color: string) {
        this._background_color = color;
    }
    /**
     * @returns {string} Color of the box
     */
     get background_color(): string {
        return this._background_color;
    }
    /**
     * @param {array} gradient - Gradient
     * @description Gradient is an array of hex color values
     * @default []
     * @example
     * //Example of a gradient
     * var gradient = ["#ff0000", "#00ff00", "#0000ff"];
     */
     set gradient(gradient: string[]) {
        this._gradient = gradient;
        this._first_gradient_color = gradient[0];
    }
    /**
     * @returns {array} Gradient
     */
     get gradient(): string[] {
        return this._gradient;
    }
}