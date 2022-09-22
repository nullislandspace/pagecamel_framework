import { CXTextBox } from "./cxtextbox.js";
import { CXArrowButton } from "./cxarrowbutton.js";
import { CXButton } from "./cxbutton.js";
import { CXScrollList } from "./cxscrolllist.js";
export class CXDropDown extends CXTextBox {
    protected _field_width: number;
    protected _field_height: number;
    protected _dropdown_button: CXButton;
    protected _dropdown_arrow: CXArrowButton;
    protected _dropdown_list: CXScrollList;
    protected _opened: boolean;
    protected _onClick: () => void;
    /**
     * @param {CanvasRenderingContext2D} ctx - the canvas context to draw on
     * @param {number} x - the x position of the element
     * @param {number} y - the y position of the element
     * @param {number} width - the width of the element
     * @param {number} height - the height of the element
     * @param {boolean} is_relative - if the element is relative to the canvas or absolute
     * @param {boolean} redraw - if the element can redraw itself
     */
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean = true, redraw: boolean = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        super.text_alignment = "left";
        super.background_color = "transparent";

        /** @protected */
        this._elements = [];
        /** @protected */
        this._field_width = 0.8;
        /** @protected */
        this._field_height = 0.2;
        /** @protected */
        this._dropdown_button = new CXButton(ctx, 0, 0, this._field_width - 0.2, this._field_height, true, false);
        /** @protected */
        this._dropdown_arrow = new CXArrowButton(ctx, this._field_width - 0.2, 0, 0.2, this._field_height, true, false);
        /** @protected */
        this._dropdown_list = new CXScrollList(ctx, 0, this._field_height, 1.0, 1.0 - this._field_height, true, false);

        this._dropdown_button.text_alignment = "center";
        this._dropdown_button.background_color = "transparent";

        this._dropdown_list.border_radius = 0;
        this._dropdown_list.item_height = 0.2 * 0.8;
        this._dropdown_list.active = false;
        this._dropdown_list.scroll_bar_width = 0.1;

        this._dropdown_arrow.background_color = "transparent";
        this._dropdown_arrow.arrow_color = "black";
        this._dropdown_arrow.arrow_direction = "down";
        /**@protected */
        this._opened = false;

        this._elements.push(this._dropdown_button);
        this._elements.push(this._dropdown_arrow);
        this._elements.push(this._dropdown_list);
        /**@protected */
        //defines what happens when the dropdown button is clicked on
        this._onClick = () => {
            console.log('Clicked on dropdown button');
            if (this._opened) {
                this._closeDropDown();
            } else {
                this._openDropDown();
            }
            this._dropdown_button.has_changed = true;
            this._dropdown_arrow.has_changed = true;
            //this._has_changed = true;
            this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        }
        this._dropdown_arrow.onClick = this._onClick;
        this._dropdown_button.onClick = this._onClick;

        this._dropdown_list.onSelect = (object, index) => {
            if (this._dropdown_list.active) {
                console.log('Selected', index);
                this._dropdown_button.text = this._dropdown_list.list[index][0];
                //this._dropdown_button.text = this._dropdown_list.list[index].text;
                this._closeDropDown();
                this._has_changed = true;
                this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
            }
        }
    }
    /**
     * @protected
     */
    protected _draw(): void {
        this._dropdown_arrow.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_button.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
        this._dropdown_list.draw(this._xpixel, this._ypixel, this._widthpixel, this._heightpixel);
    }
    /**
     * @protected
     */
    protected _openDropDown(): void {
        console.log("open");
        this._opened = true;
        this._dropdown_list.active = true;
    }
    /**
     * @protected
     */
    protected _closeDropDown(): void {
        console.log("close");
        this._dropdown_list.active = false;
        this._opened = false;
    }
    /**
     * @description handles the event
     * @params {event} event - the event
     * @public
     */
    protected _handleEvent(event: Event): boolean {
        console.log("handle event");
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this._has_changed = true;
                }
            }
        });
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        return this._has_changed;
    }
    /**
     * @param {number} width - width of the field in percent of the dropdown width
     */
    set field_width(width: number) {
        this._field_width = width;
        this._dropdown_button.width = width - 0.2;
        this._dropdown_arrow.xpos = width - 0.2;
        this._dropdown_arrow.width = 0.2;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;

    }
    get field_width(): number {
        return this._field_width;
    }
    /**
     * @param {number} value - height of the field in percent of the dropdown height
     */
    set field_height(value: number) {
        this._field_height = value;
        this._dropdown_button.height = value;
        this._dropdown_arrow.height = value;
        this._dropdown_list.ypos = value;
        this._dropdown_list.height = 1.0 - value;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get field_height(): number {
        return this._field_height;
    }
    /**
     * @param {string} value - text to be displayed in the field
     */
    set text(value: string) {
        this._dropdown_button.text = value;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get text(): string {
        return this._dropdown_button.text;
    }

    /**
     * @param {Array} string_array - 2D array of strings to be displayed in the dropdown list
     */
    set list(string_array: string[][]) {
        this._dropdown_list.list = string_array;

        //sets the height of the list items to 80% of the field height
        this._dropdown_list.item_height = this._field_height * 0.8;
        console.log('New item height: ' + this._dropdown_list.item_height);
        //sets the height of the list to the height of the items or the height of the dropdown - the field height
        this._dropdown_list.height = Math.min(this._dropdown_list.item_height * string_array.length, 1.0 - this._field_height);
        console.log('New Height:', this._dropdown_list.height);
        //sets the height of the dropdown to the height of the field + the height of the list
        this._dropdown_list.item_height = (this._field_height / this._dropdown_list.height) * 0.8;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get list(): string[][] {
        return this._dropdown_list.list;
    }
    /**
     * @param {string} color - background_color color of the field
     */
    set background_color(color: string) {
        this._dropdown_button.background_color = color;
        this._dropdown_arrow.background_color = color;
        this._dropdown_list.background_color = color;
        this._tryRedraw(this._px, this._py, this._pwidth, this._pheight);
        this._has_changed = true;
    }
    get background_color(): string {
        return this._dropdown_button.background_color;
    }
}