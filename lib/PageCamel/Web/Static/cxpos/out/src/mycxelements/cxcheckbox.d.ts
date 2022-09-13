declare class CXCheckBox {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _box: any;
    _checked: boolean;
    _background: string;
    frame_color: string;
    _font_size: number;
    _setChecked(): void;
    _has_changed: boolean;
    onUncheck: () => void;
    onCheck: () => void;
    _draw(): void;
    _xpixel: any;
    _widthpixel: any;
    handleEvent(event: any): void;
    /**
     * @returns {boolean}
     * @public
    */
    public get checked(): boolean;
}
