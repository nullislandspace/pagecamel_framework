import { CXDefault } from "./cxdefault.js";
/**
 * @extends CXDefault 
 */
export class CXFrame extends CXDefault {
    /** @protected */
    protected _border_color: string;
    /** @protected */
    protected _radius: number;
    /** @protected */
    protected _radius_pixel: number;
    /** @protected */
    protected _border_width: number;
    /** @protected */
    protected _border_width_pixel: number;
    protected _border_relative: boolean;

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

        this._border_color = "black";
        this._radius = 0;
        this._radius_pixel = 0;
        this._border_width = 0.01;
        this._border_width_pixel = 0;
        this._border_relative = is_relative;
    }
    /**
     * @protected
     * @param {number} x - the x position of the mouse
     * @param {number} y - the y position of the mouse
     * @description Checks if the mouse is inside the frame
     * @return {boolean} - if the mouse is inside the frame
     */
    public isInside(x: number, y: number): boolean {
        return (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel);
    }
    /**
     * @description converts the radius to pixel and the border width to pixel
     * @protected
     */
    protected _convertFrameToPixel() {
        if (this._border_relative) {
            this._border_width_pixel = this._calcRelXToPixel(this._border_width, this._heightpixel);
        } else {
            this._border_width_pixel = this._border_width;
        }
        this._radius_pixel = this._calcRelXToPixel(this._radius, this._heightpixel);
    }
    /** 
     * @protected   
     * @description Converts the relative position to pixel position
    */
    protected _convertToPixel(): void {
        this._convertFrameToPixel();
    }
    /**
     * @protected
     * @description draws the frame with a radius
     */
    protected _drawRadius(): void {
        // draw rounded rectangle
        this._ctx.beginPath();
        this._ctx.moveTo(this.xpixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2), this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + this.widthpixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2), this.xpixel + this.widthpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - Math.ceil(this._border_width_pixel / 2), this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this.heightpixel - this._radius_pixel - Math.ceil(this._border_width_pixel / 2));
        this._ctx.lineTo(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2));
        this._ctx.quadraticCurveTo(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2), this.xpixel + this._radius_pixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2));
        if (this._border_width_pixel > 0) {
            this._ctx.stroke();
        }

    }
    /**
     * @protected
     */
    protected _drawFrame(): void {
        this._ctx.strokeStyle = this._border_color;
        this._ctx.lineWidth = this._border_width_pixel;
        if (this._radius_pixel > 0) {
            this._drawRadius();
        }
        else {
            if (this._border_width_pixel > 0) {
                this._ctx.strokeRect(this.xpixel + Math.ceil(this._border_width_pixel / 2), this.ypixel + Math.ceil(this._border_width_pixel / 2), this.widthpixel - this._border_width_pixel, this.heightpixel - this._border_width_pixel);
            }
        }
    }

    protected _draw(): void {
        this._drawFrame();
    }
    /**
     * @param {string} color - Color of the frame
     */
    set border_color(color: string) {
        this._border_color = color;
    }
    get border_color(): string {
        return this._border_color;
    }
    /**
     * @param {number} r - Radius of the frame
     */
    set radius(r: number) {
        this._radius = r;
    }
    get radius(): number {
        return this._radius;
    }
    /**
     * @param {number} w - Width of the frame
     */
    set border_width(w: number) {
        this._border_width = w;
    }
    get border_width(): number {
        return this._border_width;
    }
    set border_relative(state: boolean) {
        this._border_relative = state;
    }

}