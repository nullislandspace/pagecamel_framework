export class CXDefault {
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
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        this._ctx = ctx;
        this._is_relative = is_relative;
        this._elements = [];
        this._xpos = x;
        this._ypos = y;
        this._width = width;
        this._height = height;
        this._redraw = redraw;
        this._xpixel = 0;
        this._ypixel = 0;
        this._widthpixel = 0;
        this._heightpixel = 0;
        this._mouse_down = false;
        this._mouse_over = false;
        this._has_changed = false;
        this._takes_keyboard_input = false;
        this._active = true;
        this._px = 0;
        this._py = 0;
        this._pwidth = 0;
        this._pheight = 0;
        this._name = Object.getPrototypeOf(this).constructor.name;
    }
    /**code to calculate the relative positions of the element
     * @param {number} px - x position of the element in pixels
     * @param {number} py - y position of the element in pixels
     * @param {number} pwidth - width of the element in pixels
     * @param {number} pheight - height of the element in pixels
     */
    draw(px: number = 0, py: number = 0, pwidth: number = this._ctx.canvas.width, pheight: number = this._ctx.canvas.height): void {
        this._px = px;
        this._py = py;
        this._pwidth = pwidth;
        this._pheight = pheight;
        var [xpixel, ypixel, widthpixel, heightpixel] = this._calcRelativePositions(px, py, pwidth, pheight);
        this._xpixel = xpixel;
        this._ypixel = ypixel;
        this._widthpixel = widthpixel;
        this._heightpixel = heightpixel;
        this._convertToPixel();
        if (this._redraw) {
            this._clear();
        }
        this._has_changed = false;
        if (this._active) {
            this._checkOverflow(this._xpos, this._ypos, this._width, this._height);
            this._draw();
        }
    }
    /**
     * @protected
     * @description Converts the relative position to pixel position
    */
    protected _convertToPixel(): void {
        // override this function in child classes to convert the relative position to pixel position
    }
    /**
     * @param {MouseEvent} event - the event to get the mouse position from
     * @returns {Array} [x, y] - the mouse position relative to the canvas
     * @protected - should only be called by the child class
     */
    protected _eventToXY(event: MouseEvent): number[] {

        var x = event.offsetX;
        var y = event.offsetY;
        return [x, y];
    }
    /** @protected  */
    protected _clear(): void {
        if (this._redraw) {
            this._ctx.clearRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
            this._ctx.fillStyle = "#b3b3b3ff";
            this._ctx.fillRect(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        }
    }
    /** @protected  */
    protected _tryRedraw(px = 0, py = 0, pwidth = this._ctx.canvas.width, pheight = this._ctx.canvas.height): void {
        if (this._redraw && this._has_changed) {
            this.draw(px, py, pwidth, pheight);
        }
    }
    /** @protected  */
    protected _draw(): void {
        // override this function in child classes to draw the element
    }
    /** @protected  */
    protected _calcRelXToPixel(rel_x = 0, max_width = this._ctx.canvas.width): number {
        /* rel_x = relative position | size to convert to pixel position | max_width = pixel width of the area to draw in */
        var x = rel_x;
        if (this._is_relative) {
            // calculate the x position of the element relative to the canvas
            if (!isNaN(rel_x)) {
                x = rel_x * max_width;
            }
        }
        return x;
    }
    /** @protected  */
    protected _calcRelYToPixel(rel_y = 0, max_height = this._ctx.canvas.height): number {
        /* rel_y = relative position | size to convert to pixel position | max_height = pixel height of the area to draw in */
        var y = rel_y;
        if (this._is_relative) {
            // calculate the y position of the element relative to the canvas
            if (!isNaN(rel_y)) {
                y = rel_y * max_height;
            }
        }
        return y;
    }
    /**
     * Converts a pixel position to a relative position
     * @protected
     */
    protected _calcPixelXToRel(xpixel: number = 0, max_width: number = this._ctx.canvas.width): number {
        var rel: number = 0;
        rel = xpixel / max_width;
        return rel;
    }
    /** 
     * Converts a pixel position to a relative position
     * @protected  
     * */
    protected _calcPixelYToRel(ypixel: number = 0, max_height: number = this._ctx.canvas.height): number {
        var rel: number = 0;
        rel = ypixel / max_height;
        return rel;
    }
    /**
     * @protected - should only be called by the child class
     */
    protected _calcRelativePositions(px: number, py: number, pwidth: number, pheight: number): number[] {
        var xpixel = Math.floor(px + this._calcRelXToPixel(this._xpos, pwidth));
        var ypixel = Math.floor(py + this._calcRelYToPixel(this._ypos, pheight));
        var widthpixel = Math.ceil(this._calcRelXToPixel(this._width, pwidth));
        var heightpixel = Math.ceil(this._calcRelYToPixel(this._height, pheight));
        return [xpixel, ypixel, widthpixel, heightpixel];
    }
    /** @protected  */
    protected _getViewInfo(): void {
    }
    /** @protected  */
    protected _getMinSize(): void {
    }
    /** @protected  */
    protected _getMaxSize(): void {
    }
    /** @protected  */
    protected _checkEvent(event: Event): boolean {

        if (this._active) {
            switch (event.type) {
                case 'click':
                    var [mouse_x, mouse_y] = this._eventToXY(event as MouseEvent);
                    return this._checkClick(mouse_x, mouse_y);
                case 'mousemove':
                    var [mouse_x, mouse_y] = this._eventToXY(event as MouseEvent);
                    return this._checkMouseMove(mouse_x, mouse_y);
                case 'mousedown':
                    var [mouse_x, mouse_y] = this._eventToXY(event as MouseEvent);
                    return this._checkMouseDown(mouse_x, mouse_y);
                case 'mouseup':
                    var [mouse_x, mouse_y] = this._eventToXY(event as MouseEvent);
                    return this._checkMouseUp(mouse_x, mouse_y);
                case 'mouseleave':
                    var [mouse_x, mouse_y] = this._eventToXY(event as MouseEvent);
                    return this._checkMouseLeave(mouse_x, mouse_y);
                case 'keydown':
                    return this._checkKeyDown();
                case 'keyup':
                    return this._checkKeyUp();
            }
        }
        return false;
    }
    /**
     * @param {event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    checkEvent(event: Event): boolean {
        /* check if the event is affecting the element and if so return true
           else return false
           */
        return this._checkEvent(event);
    }
    /** @protected  */
    protected _checkClick(x: number, y: number): boolean {
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            return true;
        }
        return false;
    }
    /** @protected  */
    protected _checkMouseDown(x: number, y: number): boolean {
        if (x >= this._xpixel && x <= this._xpixel + this._widthpixel && y >= this._ypixel && y <= this._ypixel + this._heightpixel) {
            this._mouse_down = true;
            return true;
        }
        this._mouse_down = false;
        return false;
    }
    /** @protected  */
    protected _checkMouseMove(x: number, y: number): boolean {
        if (this._mouse_down) {
            return true;
        }
        if (x >= this.xpixel && x <= this.xpixel + this.widthpixel && y >= this.ypixel && y <= this.ypixel + this.heightpixel) {
            this._mouse_over = true;
            return true;
        }
        else if (this._mouse_over) {
            this._mouse_over = false;
            return true;
        }
        return false;
    }
    /** @protected  */
    protected _checkMouseUp(x: number, y: number): boolean {
        if (this._mouse_down) {
            this._mouse_down = false;
            return true;
        }
        return false;
    }
    /** @protected  */
    protected _checkMouseLeave(x: number, y: number): boolean {
        this._mouse_down = false;
        this._mouse_over = false;
        return true;
    }
    /** @protected  */
    protected _checkKeyDown(): boolean {
        if (this._takes_keyboard_input) {
            return true;
        }
        return false;
    }
    /** @protected  */
    protected _checkKeyUp(): boolean {
        if (this._takes_keyboard_input) {
            return true;
        }
        return false;
    }

    /** @protected  */
    protected _handleEvent(event: Event): boolean {
        // override this function in child classes
        return false;
    }
    /**
     * @param {Event} event - the event to check
     * @returns {boolean} - if the event needs to be handled
     */
    handleEvent(event: Event): boolean {
        var handled: boolean = false;
        if (this._active) {
            handled = this._handleEvent(event);
            console.debug("handled: " + this._name);
        }
        return handled;
    }
    /** @protected  */
    protected _checkOverflow(x: number, y: number, width: number, height: number): boolean {
        if (this._is_relative) {
            if (x < 0 || x > 1 || y < 0 || y > 1) {
                console.warn("Position is outside drawing area");
            }
            if (x + width > 1 || y + height > 1) {
                console.warn("Position and size is outside drawing area");
            }
        }
        else {
            if (x < 0 || x > this._ctx.canvas.width || y < 0 || y > this._ctx.canvas.height) {
                console.warn("Position is outside drawing area");
            }
            if (x + width > this._ctx.canvas.width || y + height > this._ctx.canvas.height) {
                console.warn("Position and size is outside drawing area");
            }
        }
        return false;
    }
    /**
    * @param {number} width
    * @public - accessible from outside the class
    */
    set width(width: number) {
        this._width = width;
    }
    get width(): number {
        return this._width;
    }
    /**
     * @param {number} height
     * @public - accessible from outside the class
     */
    set height(height: number) {
        this._height = height;
    }
    get height(): number {
        return this._height;
    }
    /**
     * @param {number} x
     * @public - accessible from outside the class
     */
    set xpos(x: number) {
        this._xpos = x;
    }
    get xpos(): number {
        return this._xpos;
    }
    /**
     * @param {number} y
     * @public - accessible from outside the class
     */
    set ypos(y: number) {
        this._ypos = y;
    }
    get ypos(): number {
        return this._ypos;
    }
    /**
     * @param {boolean} state
     * @public - accessible from outside the class
     */
    set is_relative(state: boolean) {
        this._is_relative = state;
    }
    get is_relative(): boolean {
        return this._is_relative;
    }
    /**
     * @param {boolean} changed
     */
    set has_changed(changed: boolean) {
        this._has_changed = changed;
    }
    get has_changed(): boolean {
        return this._has_changed;
    }
    get xpixel(): number {
        return this._xpixel;
    }
    get ypixel(): number {
        return this._ypixel;
    }
    get widthpixel(): number {
        return this._widthpixel;
    }
    get heightpixel(): number {
        return this._heightpixel;
    }
    /**
     * @param {boolean} state - if the element is visible or not
     */
    set active(state: boolean) {
        this._tryRedraw();
        this._active = state;
    }
    get active(): boolean {
        this._tryRedraw();
        return this._active;
    }
    /**
     * @param {string} name - the name of the element
     */
    set name(name: string) {
        this._name = name;
    }
    get name(): string {
        return this._name;
    }
    /**
     * Sets the attributes of the element if they are public
     * @param attributes - the attributes to set
     * @example element.attributes = {xpos: 0.5, ypos: 0.5, width: 0.5, height: 0.5}
     */
    set attributes(attributes: object) {
        var attr = JSON.parse(JSON.stringify(attributes)); // copy to remove references to the original object 
        var keys = Object.keys(attr);
        // walk through the entire prototype chain
        for (let o = Object.getPrototypeOf(this); o && o != Object.prototype; o = Object.getPrototypeOf(o)) {
            keys.forEach((key) => {
                var descriptor = Object.getOwnPropertyDescriptor(o, key);
                // check if the attribute has a setter
                if (descriptor && descriptor.set) {
                    descriptor.set.call(this, (<any>attr)[key]);
                }
            });
        }
    }
    /**
     * Returns all the attributes of the element if they are public and are valid attributes
     * @returns - the public attributes of the element
     */
    get attributes(): object {
        var attr = {};
        // walk through the entire prototype chain
        for (let o = Object.getPrototypeOf(this); o && o != Object.prototype; o = Object.getPrototypeOf(o)) {
            Object.getOwnPropertyNames(o).forEach((key) => {
                var descriptor = Object.getOwnPropertyDescriptor(o, key);
                // check if the attribute has a getter and prevent the attributes from calling itself recursively
                if (descriptor && descriptor.get && key != "attributes") {
                    (<any>attr)[key] = descriptor.get.call(this);
                }
            });
        }
        return attr;
    }

    /**
     * Calculates the optimal width to the adjusted height, so that the buttons are squares
     * 
     *@return width - in pixel (absolute) or relative (to the parent object)
     */
     calcOptimalWidth(): number{
        let total_width = 0;
        let f_width = 0;
        let f_height = this.height;
        
        
        if (this.is_relative){
            f_width = this._calcRelYToPixel(f_height);
            total_width = this._calcPixelXToRel(f_width);
        } 
        else{
            total_width = f_height;
        } 
        
        
        

            

                
        
        console.debug("cxframe - calcOptimalWidth:" + total_width.toString());
        return total_width;
    } 

    /**
     * Calculates the optimal width to the adjusted height, so that the buttons are squares
     * 
     *@return width - in pixel (absolute) or relative (to the parent object)
     */
     calcOptimalHeight(): number{
        let total_heigth = 0;
        let f_width = this.width;
        let f_height = 0;
        
        
        if (this.is_relative){
            f_height = this._calcRelXToPixel(f_width);
            total_heigth = this._calcPixelYToRel(f_height);
        } 
        else{
            total_heigth = f_width;
        } 
        
        
        

            

                
        
        console.debug("cxframe - calcOptimalHeigth:" + total_heigth.toString());
        return total_heigth;
    } 

    /**
     * Set square size.
     * FIFO: If width not NULL -> calculate the heigth
     *       If width is NULL and heigth not NULL -> calculate the width
     * @remarks 
     * Use setSquareSize() to calculate the width to the already adjusted height
     * Use setSquareSize(this.width) to calculate the heigth to the already adjusted width
     * 
     * @param width - Width in pixel/relativ or NULL
     * @param height - Heigth in pixel/relativ or NULL   
     */
    setSquareSize(width: number|null = null, heigth: number|null = this.height): void{
        if (width != null){
            //calculate heigth to the width
            this.width = width;
            this.height = this.calcOptimalHeight();
        } 
        else if (heigth != null){
            //calculate width to the heigth
            this.height = heigth;
            this.width = this.calcOptimalWidth();
        } 
    }
}
