export declare class CXDefault {
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
    protected _name: string;
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
    /**code to calculate the relative positions of the element
     * @param {number} px - x position of the element in pixels
     * @param {number} py - y position of the element in pixels
     * @param {number} pwidth - width of the element in pixels
     * @param {number} pheight - height of the element in pixels
     */
    draw(px?: number, py?: number, pwidth?: number, pheight?: number): void;
    /**
     * @protected
     * @description Converts the relative position to pixel position
    */
    protected _convertToPixel(): void;
    /**
     * @param {MouseEvent} event - the event to get the mouse position from
     * @returns {Array} [x, y] - the mouse position relative to the canvas
     * @protected - should only be called by the child class
     */
    protected _eventToXY(event: MouseEvent): number[];
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
    protected _calcRelativePositions(px: number, py: number, pwidth: number, pheight: number): number[];
    /** @protected  */
    protected _getViewInfo(): void;
    /** @protected  */
    protected _getMinSize(): void;
    /** @protected  */
    protected _getMaxSize(): void;
    /** @protected  */
    protected _checkEvent(event: Event): boolean;
    /**
     * @param {event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    checkEvent(event: Event): boolean;
    /** @protected  */
    protected _checkClick(x: number, y: number): boolean;
    /** @protected  */
    protected _checkMouseDown(x: number, y: number): boolean;
    /** @protected  */
    protected _checkMouseMove(x: number, y: number): boolean;
    /** @protected  */
    protected _checkMouseUp(x: number, y: number): boolean;
    /** @protected  */
    protected _checkMouseLeave(x: number, y: number): boolean;
    /** @protected  */
    protected _checkKeyDown(): boolean;
    /** @protected  */
    protected _checkKeyUp(): boolean;
    /** @protected  */
    protected _handleEvent(event: Event): boolean;
    /**
     * @param {Event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    handleEvent(event: Event): boolean;
    /** @protected  */
    protected _checkOverflow(x: number, y: number, width: number, height: number): boolean;
    /**
    * @param {number} width
    * @public - accessible from outside the class
    */
    set width(width: number);
    get width(): number;
    /**
     * @param {number} height
     * @public - accessible from outside the class
     */
    set height(height: number);
    get height(): number;
    /**
     * @param {number} x
     * @public - accessible from outside the class
     */
    set xpos(x: number);
    get xpos(): number;
    /**
     * @param {number} y
     * @public - accessible from outside the class
     */
    set ypos(y: number);
    get ypos(): number;
    /**
     * @param {boolean} state
     * @public - accessible from outside the class
     */
    set is_relative(state: boolean);
    get is_relative(): boolean;
    /**
     * @param {CanvasRenderingContext2D} value
     * @public - accessible from outside the class
     */
    set ctx(value: CanvasRenderingContext2D);
    get ctx(): CanvasRenderingContext2D;
    /**
     * @param {boolean} changed
     */
    set has_changed(changed: boolean);
    get has_changed(): boolean;
    get xpixel(): number;
    get ypixel(): number;
    get widthpixel(): number;
    get heightpixel(): number;
    /**
     * @param {boolean} state - if the element is visible or not
     */
    set active(state: boolean);
    get active(): boolean;
    /**
     * @param {string} name - the name of the element
     */
    set name(name: string);
    get name(): string;
}
