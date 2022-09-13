declare class CXTextInput {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative: any, redraw: any);
    _text_alignment: string;
    _takes_keyboard_input: boolean;
    type: string;
    _always_active: boolean;
    _cursorPos: number;
    _cursor_color: string;
    _cursor_width: number;
    _cursor_active: boolean;
    _cursor_blink_interval: number;
    _cursor_visible_blink: boolean;
    _auto_line_break: boolean;
    _showCursor(x: any): void;
    _has_changed: boolean;
    _moveCursorLeft(ctrl: any): void;
    _moveCursorRight(ctrl: any): void;
    _checkMouseDown(x: any, y: any): boolean;
    _mouse_down: boolean;
    _changeText(event: any): void;
    text: any;
    _onKeyDown(event: any): boolean;
    handleEvent(event: any): void;
    _drawCursor(): void;
    _draw(): void;
}
