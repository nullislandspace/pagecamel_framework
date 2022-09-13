export class CXDefault {
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
    /** @protected  */
    protected _ctx: CanvasRenderingContext2D;
    /** @protected  */
    protected _is_relative: boolean;
    /** @protected  */
    protected _elements: any[];
    /** @protected  */
    protected _xpos: number;
    /** @protected  */
    protected _ypos: number;
    /** @protected  */
    protected _width: number;
    /** @protected  */
    protected _height: number;
    /** @protected  */
    protected _redraw: boolean;
    /** @protected  */
    protected _xpixel: number;
    /** @protected  */
    protected _ypixel: number;
    /** @protected  */
    protected _widthpixel: number;
    /** @protected  */
    protected _heightpixel: number;
    /** @protected  */
    protected _mouse_down: boolean;
    /** @protected  */
    protected _mouse_over: boolean;
    /** @protected  */
    protected _has_changed: boolean;
    /** @protected  */
    protected _takes_keyboard_input: boolean;
    /** @protected  */
    protected _active: boolean;
    /** @protected  */
    protected _px: number;
    /** @protected  */
    protected _py: number;
    /** @protected  */
    protected _pwidth: number;
    /** @protected  */
    protected _pheight: number;
    /** @protected  */
    protected _font_size_pixel: number;
    /** @protected  */
    protected _font_size: number;
    /**
     * @param {number} px - x position of the element in pixels
     * @param {number} py - y position of the element in pixels
     * @param {number} pwidth - width of the element in pixels
     * @param {number} pheight - height of the element in pixels
     */
    draw(px?: number, py?: number, pwidth?: number, pheight?: number): void;
    /**
     * @param {event} event - the event to get the mouse position from
     * @returns {Array} [x, y] - the mouse position relative to the canvas
     * @protected - should only be called by the child class
     */
    protected _eventToXY(event: Event): any[];
    /** @protected  */
    protected _clear(): void;
    /** @protected  */
    protected _tryRedraw(px?: number, py?: number, pwidth?: number, pheight?: number): void;
    /** @protected  */
    protected _draw(): void;
    /** @protected  */
    protected _calcRelXToPixel(rel_x?: number, max_width?: number): number;
    /** @protected  */
    protected _calcRelYToPixel(rel_y?: number, max_height?: number): number;
    /**
     * @protected - should only be called by the child class
     */
    protected _calcRelativePositions(px: any, py: any, pwidth: any, pheight: any): number[];
    /** @protected  */
    protected _getViewInfo(): void;
    /** @protected  */
    protected _getMinSize(): void;
    /** @protected  */
    protected _getMaxSize(): void;
    /** @protected  */
    protected _checkEvent(event: any): boolean;
    /**
     * @param {event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    checkEvent(event: Event): boolean;
    /** @protected  */
    protected _checkClick(x: any, y: any): boolean;
    /** @protected  */
    protected _checkMouseDown(x: any, y: any): boolean;
    /** @protected  */
    protected _checkMouseMove(x: any, y: any): boolean;
    /** @protected  */
    protected _checkMouseUp(x: any, y: any): boolean;
    /** @protected  */
    protected _checkMouseLeave(x: any, y: any): boolean;
    /** @protected  */
    protected _checkKeyDown(): boolean;
    /** @protected  */
    protected _checkKeyUp(): boolean;
    /**
     * @param {event} event - the event to check
     * @param {callback} function
     * @returns {boolean} - if the event needs to be handled
     */
    handleEvent(event: Event, callback: any): boolean;
    /** @protected  */
    protected _checkOverflow(x: any, y: any, width: any, height: any): boolean;
    /**
    * @param {number} width
    * @public - accessible from outside the class
    */
    set width(arg: number);
    get width(): number;
    /**
     * @param {number} height
     * @public - accessible from outside the class
     */
    set height(arg: number);
    get height(): number;
    /**
     * @param {number} x
     * @public - accessible from outside the class
     */
    set xpos(arg: number);
    get xpos(): number;
    /**
     * @param {number} y
     * @public - accessible from outside the class
     */
    set ypos(arg: number);
    get ypos(): number;
    /**
     * @param {boolean} state
     * @public - accessible from outside the class
     */
    set is_relative(arg: boolean);
    get is_relative(): boolean;
    /**
     * @param {CanvasRenderingContext2D} value
     * @public - accessible from outside the class
     */
    set ctx(arg: CanvasRenderingContext2D);
    get ctx(): CanvasRenderingContext2D;
    /**
     * @param {boolean} changed
     */
    set has_changed(arg: boolean);
    get has_changed(): boolean;
    get xpixel(): number;
    get ypixel(): number;
    get widthpixel(): number;
    get heightpixel(): number;
    /**
     * @param {number} font_size
     * @public - accessible from outside the class
     */
    set font_size(arg: number);
    get font_size(): number;
    /**
     * @param {boolean} state - if the element is visible or not
     */
    set active(arg: boolean);
    get active(): boolean;
}
//# sourceMappingURL=cxdefault.d.ts.map