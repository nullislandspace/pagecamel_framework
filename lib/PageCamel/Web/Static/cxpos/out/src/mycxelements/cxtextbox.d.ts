import { CXBox } from "./cxbox.js";
/**
 * @extends CXBox
 */
export declare class CXTextBox extends CXBox {
    /** @protected */
    protected _text_color: string;
    /** @protected */
    protected _font_family: string;
    /** @protected  */
    protected _font_size_pixel: number;
    /** @protected  */
    protected _font_size: number;
    /** @protected */
    protected _text: string;
    /** @protected */
    protected _text_alignment: string;
    /** @protected */
    protected _auto_line_break: boolean;
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
     * @description converts the font size to pixel size
     * @protected
     */
    protected _convertFontSizeToPixel(): void;
    /**
     * @protected
     * @description Converts the relative position to pixel position
    */
    protected _convertToPixel(): void;
    /**
     * @protected
     */
    protected _drawText(): void;
    /**
     * @protected
     * @param {string} text - Text to break into lines if it is too long
     * @param {number} max_width - Maximum width of the text
     * @description autoLineBreak will break the text into lines if it is too long preferably at a space and if there is no space it will break it at a word
     * @returns {string[]}
     */
    protected _autoLineBreak(text: string, maxWidth: any): string[];
    /**
     * @protected
     */
    protected _drawTextBox(): void;
    /**
     * @protected
     */
    protected _draw(): void;
    /**
     * @param {string} color - Color of the text
     * @default "black"
     */
    set text_color(color: string);
    get text_color(): string;
    /**
     * @param {string} font - Font family of the text
     * @default "Arial"
     */
    set font_family(font: string);
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
    set text(text: string);
    get text(): string;
    /**
     * @param {string} textalign - Text alignment
     * @description Possible values are "left", "center" and "right"
     * @default "center"
     */
    set text_alignment(textalign: string);
    get text_alignment(): string;
    /**
     * @param {boolean} lbreak - Auto line break
     * @description If true, the text will be automatically line broken
     * @default true
     */
    set auto_line_break(lbreak: boolean);
    get auto_line_break(): boolean;
    /**
     * @param {number} fsize
     * @public - accessible from outside the class
     */
    set font_size(fsize: number);
    get font_size(): number;
}
