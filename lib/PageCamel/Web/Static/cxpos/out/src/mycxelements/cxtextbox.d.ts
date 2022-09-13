export class CXTextBox extends CXBox {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _text_color: string;
    _font_family: string;
    _font_size: number;
    _text: string;
    _text_alignment: string;
    _auto_line_break: boolean;
    _font_size_pixel: number;
    _drawText(): void;
    _autoLineBreak(ctx: any, text: any, maxWidth: any): string[];
    _drawTextBox(): void;
    /**
     * @param {string} color - Color of the text
     * @default "black"
     */
    set text_color(arg: string);
    get text_color(): string;
    /**
     * @param {string} font_family - Font family of the text
     * @default "Arial"
     */
    set font_family(arg: string);
    get font_family(): string;
    /**
     * @param {string} font_size - Font size of the text
     * @description Font size is in em
     * @default "0.5 or 12px"
     */
    /**
     * @param {string} text - Text to be displayed
     * @description If the text is an array, each element will be displayed on a new line
     * @default ""
     */
    set text(arg: string);
    get text(): string;
    /**
     * @param {string} text_alignment - Text alignment
     * @description Possible values are "left", "center" and "right"
     * @default "center"
     */
    set text_alignment(arg: string);
    get text_alignment(): string;
    /**
     * @param {boolean} auto_line_break - Auto line break
     * @description If true, the text will be automatically line broken
     * @default true
     */
    set auto_line_break(arg: boolean);
    get auto_line_break(): boolean;
}
import { CXBox } from "./cxbox.js";
