declare class CXNumPad {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _buttons_text: string[][];
    _buttons: any[][];
    _gap: number;
    _font_size: number;
    _drawNumpad(): void;
    _draw(): void;
    handleEvent(event: any): void;
    /**
    * @param {number} value - Font size in either pixels or relative to button size
    * @description Sets the font size of the text in the button
    */
    set font_size(arg: number);
    get font_size(): number;
    /**
     * @param {number} value - The gap between buttons in either pixels or relative to button size
     * @description Sets the gap between buttons
     */
    set gap(arg: number);
    get gap(): number;
}
