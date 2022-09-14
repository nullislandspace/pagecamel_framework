import { CXDefault } from "./cxdefault.js";
export declare class CXFrame extends CXDefault {
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
    /** @protected */
    protected _name: string;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative?: boolean, redraw?: boolean);
    /**
     * @protected
     * @param {number} x - the x position of the mouse
     * @param {number} y - the y position of the mouse
     * @description Checks if the mouse is inside the frame
     * @return {boolean} - if the mouse is inside the frame
     */
    protected _isInside(x: number, y: number): boolean;
    /**
     * @description converts the radius to pixel and the border width to pixel
     * @protected
     */
    protected _convertFrameToPixel(): void;
    /**
     * @protected
     * @description Converts the relative position to pixel position
    */
    protected _convertToPixel(): void;
    /**
     * @protected
     * @description draws the frame with a radius
     */
    protected _drawRadius(): void;
    /**
     * @protected
     */
    protected _drawFrame(): void;
    protected _draw(): void;
    /**
     * @param {string} color - Color of the frame
     */
    set border_color(arg: string);
    get border_color(): string;
    /**
     * @param {number} r - Radius of the frame
     */
    set radius(arg: number);
    get radius(): number;
    /**
     * @param {number} w - Width of the frame
     */
    set border_width(arg: number);
    get border_width(): number;
}
