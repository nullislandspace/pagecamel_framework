export class CXBox extends CXFrame {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _background: string;
    _gradient: any[];
    _first_gradient_color: string;
    _drawBox(): void;
    /**
     * @param {string} color - Color of the box
     */
    set background(arg: string);
    get background(): string;
    /**
     * @param {array} gradient - Gradient
     * @description Gradient is an array of hex color values
     * @default []
     * @example
     * //Example of a gradient
     * var gradient = ["#ff0000", "#00ff00", "#0000ff"];
     */
    set gradient(arg: any[]);
    get gradient(): any[];
}
import { CXFrame } from "./cxframe.js";
