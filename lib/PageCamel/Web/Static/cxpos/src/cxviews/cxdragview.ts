import { CXDefaultView } from './cxdefaultview.js';
import { CXDragAndDropRect } from '../cxelements/cxdraganddroprect.js';
import { CXDragAndDropEllipse } from '../cxelements/cxdraganddropellipse.js';
import { CXDragAndDropText } from '../cxelements/cxdraganddroptext.js';
import { CXButton } from '../cxelements/cxbutton.js';

export class CXDragView extends CXDefaultView {
    protected _draw_mode: string = 'none';
    private _draganddrops: Array<CXDragAndDropRect> = [];
    protected _draw_draganddrop: any;
    protected _drawMouseDownX: number | null = null;
    protected _drawMouseDownY: number | null = null;

    protected _selectedDragAndDrop: CXDragAndDropRect | null = null;
    protected _count: number = 0;
    protected _drawModes = {
        'rect': CXDragAndDropRect,
        'circle': CXDragAndDropEllipse,
        'text': CXDragAndDropText,
        'img': CXDragAndDropRect
    };
    protected _draganddropImage: string = "";
    protected _allow_editing: boolean = false;

    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this.border_width = 0.001;
        this.background_color = '#fff';
        this._draw_draganddrop = null;
    }
    protected _initialize(): void {

    }
    protected _draw(): void {
        super._draw();
        this._draganddrops.forEach(draganddrop => {
            draganddrop.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        });
        if (this._draw_draganddrop) {
            this._draw_draganddrop.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        }
    }
    /**
     * Gets called when the mouse gets released and it is in the draw mode
     */
    protected _finishCreation(): void {
        if (this._draw_draganddrop && this._drawMouseDownX && this._drawMouseDownY) {
            var width: number = this._calcRelXToPixel(this._draw_draganddrop.width, this._widthpixel);
            var height: number = this._calcRelYToPixel(this._draw_draganddrop.height, this._heightpixel);
            var min_width_height = this._draw_draganddrop.minWidthHeight;

            //set the minimum width and height
            if (width < min_width_height) {
                width = min_width_height;
            }
            if (height < min_width_height) {
                height = min_width_height;
            }
            this._draw_draganddrop.width = this._calcPixelXToRel(width, this._widthpixel);
            this._draw_draganddrop.height = this._calcPixelYToRel(height, this._heightpixel);

            //prevent element from being outside of the view
            if (this._draw_draganddrop.xpos + this._draw_draganddrop.width > 1.0) {
                this._draw_draganddrop.xpos = 1.0 - this._draw_draganddrop.width;
            }
            if (this._draw_draganddrop.ypos + this._draw_draganddrop.height > 1.0) {
                this._draw_draganddrop.ypos = 1.0 - this._draw_draganddrop.height;
            }

            //add the element to the view
            this._draganddrops.push(this._draw_draganddrop);
            this._draw_draganddrop = null;
            this._drawMouseDownX = null;
            this._drawMouseDownY = null;

        }
    }
    protected _handleEvent(event: Event): boolean {
        var [x, y] = this._eventToXY(event as MouseEvent);
        var xrel = this._calcPixelXToRel(x, this._widthpixel);
        var yrel = this._calcPixelYToRel(y, this._heightpixel);
        if (xrel > 0 && xrel < 1 && yrel > 0 && yrel < 1) {
            if (event.type === 'mousedown') {
                if (this._draw_mode !== 'none' && this._draw_mode !== 'select') {
                    this._drawMouseDownX = xrel;
                    this._drawMouseDownY = yrel;
                    // creates new draganddrop element depending on the draw mode
                    this._draw_draganddrop = new (<any>this._drawModes)[this._draw_mode](this._ctx, xrel, yrel, 0.001, 0.001, true, false);
                    this._draw_draganddrop.onClick = (obj: CXButton) => this.onDragAndDropClick(obj);
                    this._draw_draganddrop.name = String(this._count);
                    this._draw_draganddrop.text = String(this._draw_draganddrop.name);
                    if (this._draw_mode === 'img') {
                        this._draw_draganddrop.background_image = this._draganddropImage;
                    }
                    this._count++;
                    this._draw_draganddrop.border_relative = false;
                    this._draw_draganddrop.border_width = 15;
                    this._draw_draganddrop.resizeable = false;
                }
            }
            else if (event.type === 'mousemove') {
                if (this._draw_draganddrop && this._drawMouseDownX && this._drawMouseDownY) {
                    // handles the drawing of the new dragable element
                    if (xrel > this._drawMouseDownX) {
                        this._draw_draganddrop.xpos = this._drawMouseDownX;
                        this._draw_draganddrop.width = xrel - this._drawMouseDownX;
                    }
                    else {
                        this._draw_draganddrop.xpos = xrel;
                        this._draw_draganddrop.width = this._drawMouseDownX - xrel;
                    }
                    if (yrel > this._drawMouseDownY) {
                        this._draw_draganddrop.ypos = this._drawMouseDownY;
                        this._draw_draganddrop.height = yrel - this._drawMouseDownY;
                    }
                    else {
                        this._draw_draganddrop.ypos = yrel;
                        this._draw_draganddrop.height = this._drawMouseDownY - yrel;
                    }
                }
            }
            else if (event.type === 'mouseup') {
                this._finishCreation();
            }
            this._has_changed = true;
        }
        //loop through all drag and drop elements reverse order
        if (this._draw_mode === 'select' || this.allow_editing === false) {
            var handled = false;
            var handled_index = -1;
            for (var i = this._draganddrops.length - 1; i >= 0; i--) {
                var draganddrop = this._draganddrops[i];
                if (draganddrop.checkEvent(event)) {
                    if (handled === false) {
                        //first element that is handled will be on top and will be the one that is selected
                        draganddrop.handleEvent(event);
                    }
                    if (draganddrop.has_changed && draganddrop.show_resize_frame) {
                        // the event is handled if the resize frame is shown and the element has changed
                        //console.log('draganddrop has changed' + draganddrop.name);
                        handled = true;
                        handled_index = i;
                        this._has_changed = true;
                    }
                }
            }
            if (handled) {
                //remove draganddrop that was handled and add it to the end of the list so it is drawn on top
                var handled_draganddrop = this._draganddrops[handled_index];
                /* if (this._draganddrops[handled_index].move_dragndrop) {
                    console.log('handled draganddrop: ' + handled_draganddrop.name);
                } */
                this._draganddrops.splice(handled_index, 1);
                this._draganddrops.push(handled_draganddrop);
                this._selectedDragAndDrop = handled_draganddrop;
                for (var i = 0; i < this._draganddrops.length - 1; i++) {
                    this._draganddrops[i].show_resize_frame = false;
                    this._draganddrops[i].move_dragndrop = false;
                }
            }
            else if (event.type === 'mousedown') {
                //if no draganddrop click was handled, then deselect all draganddrops
                this._selectedDragAndDrop = null;
                for (var i = 0; i < this._draganddrops.length; i++) {
                    this._draganddrops[i].show_resize_frame = false;
                    this._draganddrops[i].move_dragndrop = false;
                }
            }

        }

        this._tryRedraw();
        return this._has_changed;
    }
    /**
     * Set the draw mode of the view (rect, circle, img, text, select, none) for drawing a new dragable element
     * @param mode
     */
    set draw_mode(mode: string) {
        this._finishCreation();
        if (mode !== 'none' && mode !== 'select') {
            //show crosshair cursor
            this._ctx.canvas.style.cursor = 'crosshair';
            //this._draganddrop.default_cursor = 'crosshair';
            //this._draganddrop.show_resize_frame = false;
            this._draganddrops.forEach(draganddrop => {
                draganddrop.show_resize_frame = false;
                draganddrop.resizeable = false;
                this._selectedDragAndDrop = null;
            });
        }
        else {
            this._ctx.canvas.style.cursor = 'default';
            this._draganddrops.forEach(draganddrop => {
                draganddrop.resizeable = true;
            });
            //this._draganddrop.default_cursor = 'default';
        }
        this._draw_mode = mode;
        this._tryRedraw();
    }
    get draw_mode(): string {
        return this._draw_mode;
    }
    set draganddropImage(image: string) {
        this._draganddropImage = image;
        if (this._draw_draganddrop && this._draw_mode === 'img') {
            this._draw_draganddrop.background_image = image;
        }
    }
    get draganddropImage(): string {
        return this._draganddropImage;
    }
    /**
     * delete the selected drag and drop element
     */
    deleteSelectedDragAndDrop() {
        if (this._selectedDragAndDrop) {
            var index = this._draganddrops.indexOf(this._selectedDragAndDrop);
            if (index > -1) {
                this._draganddrops.splice(index, 1);
            }
            this._selectedDragAndDrop = null;
            this._has_changed = true;
            this._tryRedraw();
        }
    }
    /**
     * duplicate the selected drag and drop element
     */
    duplicateSelectedDragAndDrop() {
        if (this._selectedDragAndDrop) {
            var index = this._draganddrops.indexOf(this._selectedDragAndDrop);
            if (index > -1) {
                console.log('duplicate drag and drop');
                var new_draganddrop = this._selectedDragAndDrop.clone();
                this._count++;
                new_draganddrop.name = String(this._count);
                new_draganddrop.text = String(this._count);
                //moves the new draganddrop a bit to the right and down
                new_draganddrop.xpos += 0.05;
                new_draganddrop.ypos += 0.05;

                //check for overflow of the new draganddrop and move it to start if it is outside the view
                if (new_draganddrop.xpos + new_draganddrop.width > 1) {
                    new_draganddrop.xpos = 0;
                }
                if (new_draganddrop.ypos + new_draganddrop.height > 1) {
                    new_draganddrop.ypos = 0;
                }
                this._selectedDragAndDrop.show_resize_frame = false;
                this._selectedDragAndDrop = new_draganddrop;
                //add the new draganddrop to the list
                this._draganddrops.push(new_draganddrop);

            }
            this._has_changed = true;
            this._tryRedraw();
        }
    }
    getAllDragAndDrops(): Array<object> {
        var draganddrops_attributes: object[] = [];
        this._draganddrops.forEach(element => {
            draganddrops_attributes.push(element.attributes);
        });
        return draganddrops_attributes;
    }
    /**
     * Set what happens when the user clicks the draganddrop
     * Ovewrite this function 
     */
    onDragAndDropClick = (obj: CXButton) => {
        console.log('click on draganddrop');
    }
    get selectedDragAndDrop(): CXDragAndDropRect | CXDragAndDropEllipse | CXDragAndDropText | null {
        return this._selectedDragAndDrop;
    }
    set allow_editing(allow: boolean) {
        this._draganddrops.forEach(draganddrop => {
            if (!allow) {
                draganddrop.show_resize_frame = allow;
            }
            draganddrop.move_dragndrop = allow;
            draganddrop.resizeable = allow;
            draganddrop.dragable = allow;
        });
        this._allow_editing = allow;
    }
    get allow_editing(): boolean {
        return this._allow_editing;
    }
    set draganddrops(draganddrops: Array<object>) {
        this._draganddrops = [];
        draganddrops.forEach(element => {
            var draganddrop = new CXDragAndDropRect(this._ctx, 0, 0, 0, 0, true, false);
            draganddrop.attributes = element;
            draganddrop.onClick = (obj:CXButton) => this.onDragAndDropClick(obj);
            this._draganddrops.push(draganddrop);
        });
        this._has_changed = true;
        this._tryRedraw();
    }

}