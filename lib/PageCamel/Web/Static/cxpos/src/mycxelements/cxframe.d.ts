export class CXFrame extends CXDefault {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _frame_color: string;
    _radius: number;
    _border_width: number;
    _isInside(x: any, y: any): boolean;
    _drawRadius(): void;
    _drawFrame(): void;
    /**
     * @param {string} color - Color of the frame
     */
    set frame_color(arg: string);
    get frame_color(): string;
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
import { CXDefault } from "../cxdefault.js";
