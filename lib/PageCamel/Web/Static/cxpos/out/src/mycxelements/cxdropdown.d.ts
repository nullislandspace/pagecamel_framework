declare class CXDropDown {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _elements: any[];
    _field_width: number;
    _field_height: number;
    _dropdown_button: any;
    _dropdown_arrow: CXArrowButton;
    _dropdown_list: any;
    _opened: boolean;
    onClick: () => void;
    _draw(): void;
    _openDropDown(): void;
    _closeDropDown(): void;
    handleEvent(event: any): void;
    _has_changed: boolean;
    /**
     * @param {number} value - width of the field in percent of the dropdown width
     */
    set field_width(arg: number);
    get field_width(): number;
    /**
     * @param {number} value - height of the field in percent of the dropdown height
     */
    set field_height(arg: number);
    get field_height(): number;
    /**
     * @param {string} value - text to be displayed in the field
     */
    set text(arg: string);
    get text(): string;
    /**
     * @param {Array} string_array - 2D array of strings to be displayed in the dropdown list
     */
    set list(arg: any[]);
    get list(): any[];
    /**
     * @param {String} value - background color of the field
     */
    set background(arg: string);
    get background(): string;
}
