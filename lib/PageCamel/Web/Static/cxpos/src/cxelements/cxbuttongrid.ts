import { CXNumPad } from './cxnumpad';

export class CXButtonGrid extends CXNumPad {
    protected _buttons_text_block: (string|null)[][];
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative: boolean, redraw: boolean) {
        super(ctx, x, y, width, height, is_relative, redraw);

    }
    
}
