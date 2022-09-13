/* import { CXDefault } from "./mycxelements/cxdefault.js"; 
import { CXFrame }   from "./mycxelements/cxframe.js";
import { CXBox}  from "./mycxelements/cxbox.js";
import { CXTextBox}  from "./mycxelements/cxtextbox.js";
import { CXButton } from "./mycxelements/cxbutton.js"; 
import { CXScrollList } from "./mycxelements/cxscrolllist.js"; 



export class CXTestView extends CXDefault {
    protected viewelements : any[] = [];
    private _leftlist : CXScrollList;
    private _infotext : CXTextBox;
    constructor(ctx:CanvasRenderingContext2D, x:number, y:number, width:number, height:number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initialize();
    } 

    private _initialize(){
        let viewborder = new CXFrame(this._ctx,0,0,1,1,true,false);
        viewborder.border_width=5;
        viewborder.frame_color="808080ff";
        this.viewelements.push(viewborder);
        
        let cxbox = new CXButton(this._ctx,0.41,0.1,0.2,0.1,true,false);
        cxbox.gradient = ['#87de87ff','#008000ff'];
        cxbox.frame_color = '#ffffffff';
        cxbox.border_width = 5;
        cxbox.radius = 10;
        cxbox.text = "BAR";
        this.viewelements.push(cxbox);
        let cxlist = new CXScrollList(this._ctx,0.1,0.21,0.3,0.75,true,false);
        let litems =[];
        for (let i=0; i<40; i++){
            litems[i] = ['Zeile ' + (i+1), 'Spalte 1.' + (i+1), 'Spalte 2.' + (i+1)] ;
        } 
        cxlist.list = litems;
        cxlist.background = "#ffffffff";
        cxlist.item_height = 0.04;
        //this._onListSelect.bind(cxlist);
        cxlist.onSelect =  this._onListSelect;
        this.viewelements.push(cxlist);
        this._leftlist = cxlist;
        //Textbox
        let textbox = new CXTextBox(this._ctx, 0.1, 0.1, 0.3, 0.1, true, false);
        textbox.background = "#ffffffff";
        textbox.frame_color = "#808080ff"
        textbox.border_width = 5;
        textbox.radius = 10;
        textbox.font_size = 0.2;
        this.viewelements.push(textbox);
        this._infotext = textbox;
        
    } 

    public handleEvent(e:Event):boolean {
        let reDR = false;
        let retval = false;
        for (let i=0; i<this.viewelements.length; ++i){
            if (this.viewelements[i].checkEvent(e)){
                this.viewelements[i].handleEvent(e);
                reDR = true;
                retval = true;
            } 
        } 
        if (reDR && this._redraw){
            this.draw();
        } 
        return retval;
        
    }

    protected _draw(){
        for (let i=0 ; i<this.viewelements.length; ++i)  {
            this.viewelements[i].draw();
        } 
    } 

    
    //List-Select handler
    private _onListSelect = (listindex : number) => {
        let listitem = this._leftlist.list[listindex];
        let text = "";
        for (let i=0; i<listitem.length; i++){
            text ="Selected item " + listindex + " : " + listitem[i];
        } 
        this._infotext.text = text;
        

    } 

    


   

    
}  */