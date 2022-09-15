import { CXFrame } from "./cxframe.js";
/**
 * @extends CXFrame
 */
export declare class CXBox extends CXFrame {
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
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative?: boolean, redraw?: boolean);
    /**
     * @description Draws the box
     * @protected
     */
    protected _drawBox(): void;
    /**
     * @description Draws everything
     * @protected
     */
    protected _draw(): void;
    /**
     * @param {string} color - Color of the box
     */
    set background_color(color: string);
    /**
     * @returns {string} Color of the box
     */
    get background_color(): string;
    /**
     * @param {array} gradient - Gradient
     * @description Gradient is an array of hex color values
     * @default []
     * @example
     * //Example of a gradient
     * var gradient = ["#ff0000", "#00ff00", "#0000ff"];
     */
    set gradient(gradient: string[]);
    /**
     * @returns {array} Gradient
     */
    get gradient(): string[];
}
