declare class CXDragView {
    constructor(ctx: any, x: any, y: any, width: any, height: any, is_relative?: boolean, redraw?: boolean);
    _draganddrop: CXDragAndDrop;
    _draw(): void;
    handleEvent(event: any): void;
    _has_changed: boolean;
}
