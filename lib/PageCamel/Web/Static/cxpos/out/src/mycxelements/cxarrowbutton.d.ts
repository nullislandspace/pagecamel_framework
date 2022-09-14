declare class CXArrowButton {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _arrow_color: string;
    _arrow_width: number;
    _arrow_height: number;
    _arrow_direction: string;
    _arrow_width_pixel: number;
    _arrow_height_pixel: number;
    _drawArrow(): void;
    _draw(): void;
    set arrow_color(arg: string);
    get arrow_color(): string;
    set arrow_width(arg: number);
    get arrow_width(): number;
    set arrow_height(arg: number);
    get arrow_height(): number;
    set arrow_direction(arg: string);
    get arrow_direction(): string;
}
