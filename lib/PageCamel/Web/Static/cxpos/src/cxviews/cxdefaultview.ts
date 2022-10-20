import { CXBox } from "../cxelements/cxbox.js";
import { CXTable } from "../cxadds/cxtable.js";
import { PCWebsocket } from "../../../pcwebsocket/src/websocket.js";
export class CXDefaultView extends CXBox {
    private _table: CXTable;
    private _isconnected : boolean = false;

    protected _pcwebsocket: PCWebsocket | null = null;
    // attributes for a button with a general function 
    protected _general_func_buttons: { border_radius: number, gradient: string[], border_color: string, border_width: number } = {
        border_radius: 0.1,
        gradient: ['#80b3ffff', '#1193eeff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };
    // attributes for a button with a general function 
    protected _numpad_buttons: { border_radius: number, gradient: string[], border_color: string, border_width: number } = {
        border_radius: 0.1,
        gradient: ['#f98a03ff', '#ff0202ff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };

    // attributes for a button with a special function
    protected _special_func_buttons: { border_radius: number, gradient: string[], border_color: string, border_width: number } = {
        border_radius: 0.1,
        gradient: ['#80b3ffff', '#1193eeff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };
    // attributes for a "BAR-Button"
    protected _bar_buttons: { border_radius: number, gradient: string[], border_color: string, border_width: number } = {
        border_radius: 0.1,
        gradient: ['#87de87ff', '#008000ff'],
        border_color: '#eeeeeeff',
        border_width: 0.02,
    };
    // attributes for a "Textbox / Textinputbox"
    protected _textbox: { border_radius: number, border_color: string, border_width: number, background_color: string } = {
        border_radius: 0.05,
        border_color: "#808080ff",
        border_width: 0.02,
        background_color: '#ffffffff',
    };
    constructor(ctx: CanvasRenderingContext2D, x: number = 0, y: number = 0, width: number = 1.0, height: number = 1.0, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._table = new CXTable();
        this.background_color = '#b3b3b3ff';
        this.border_width = 0;
    }


    protected _handleEvent(event: Event): boolean {
        this._elements.forEach(element => {
            if (element.checkEvent(event)) {
                element.handleEvent(event);
                if (element.has_changed) {
                    this._has_changed = true;
                }
            }
        });
        this._tryRedraw();
        return this._has_changed;
    }

    protected _draw() {
        super._draw();
        this._elements.forEach(element => {
            element.draw(super._px, super._py, super._pwidth, super._pheight);
        });
    }

    protected _connectStatusChanged(messagename : string, isconnected : string):void {
        this._isconnected = (isconnected == '1');
        if(this._isconnected) {
            this._handleWebsocketConnect();
        } else {
            this._handleWebsocketDisconnect();
        }
    }

    protected _handleWebsocketConnect():void {
        return;
    }

    protected _handleWebsocketDisconnect():void {
        return;
    }

    /**
     * @param table - The table for the view to work with
     */
    set Table(table: CXTable) {
        this._table = table;
    }
    get Table(): CXTable {
        return this._table;
    }
    set pcwebsocket(pcwebsocket: PCWebsocket | null) {
        this._pcwebsocket = pcwebsocket;
        this._pcwebsocket?.register('ISCONNECTED', [this._connectStatusChanged.bind(this)]);
    }
    get pcwebsocket(): PCWebsocket | null {
        return this._pcwebsocket;
    }
    
}