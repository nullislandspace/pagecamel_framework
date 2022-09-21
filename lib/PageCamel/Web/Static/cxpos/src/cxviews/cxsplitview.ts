import { CXDefaultView } from './cxdefaultview.js';
import * as cxe from '../cxelements/cxelements.js';
import * as cxa from '../cxadds/cxadds.js';


export class CXSplitView extends CXDefaultView {

    private _bookingLists: { left: cxe.CXScrollList | null, right: cxe.CXScrollList | null } = { left: null, right: null };
    private _leftList: string[][] = [[]];
    private _rightList: string[][] = [[]];

    protected _initialize(): void {
        const listx = 0.05;
        const listy = 0.15;
        const listh = 1 - 2 * listy;
        const listw = 0.5 - 1.5 * listx;
        const leftList = new cxe.CXScrollList(this._ctx, listx, listy, listw, listh, true, false);
        leftList.attributes = { background_color: "white", border_width: 0.01, border_color: "#808080ff" };

        this._elements.push(leftList);

        const rightList = new cxe.CXScrollList(this._ctx, 1 - leftList.width - leftList.xpos, leftList.ypos, leftList.width, leftList.height, true, false);
        rightList.attributes = { background_color: "white", border_width: 0.01, border_color: "#808080ff" };
        this._elements.push(rightList);

        const arrw = (rightList.xpos - listx - listw) * 0.9;
        const arrh = arrw;
        const arrx = rightList.xpos - (rightList.xpos - (leftList.xpos + leftList.width)) / 2 - arrw / 2;
        const arry = rightList.ypos + rightList.height / 2 - arrh / 2;
        const arrowtext = new cxe.CXTextBox(this._ctx, arrx, arry, arrw, arrh, true, false);
        arrowtext.attributes = { background_color: this.background_color, border_color: this.background_color, text: "\u{21CB}", font_size: 0.99 };
        this._elements.push(arrowtext);

        leftList.onSelect = (obj: cxe.CXScrollList, index: number) => this._onLeftListClick;
        rightList.onSelect = (obj: cxe.CXScrollList, index: number) => this._onRightListClick;
        //this._leftList = this.Table.List();
        this._leftList = [["1", "Artikel1", "24.40"], ["1", "Artikel2", "50.50"]];
        leftList.list = this._leftList;
        this._rightList = [];
        rightList.list = this._rightList;

        this._bookingLists = { left: leftList, right: rightList };



    }

    private _onLeftListClick(obj: cxe.CXScrollList, index: number): void {
        console.debug(`Index:{index}`);
        this._rightList.push(this._leftList[index]);
        this._leftList.slice(index);
        this._bookingLists.left!.list = this._leftList;
        this._bookingLists.right!.list = this._rightList;
        this._bookingLists.left!.draw();
        this._bookingLists.left!.draw();
    }

    private _onRightListClick(obj: cxe.CXScrollList, index: number): void {

    }

    /*protected _handleEvent(event: Event): boolean {
        let fret = false;

        return fret;
    } 

    protected _draw(): void{

    } */
} 