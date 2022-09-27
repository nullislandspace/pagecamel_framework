import { CXDefaultView } from './cxdefaultview.js';
import * as cxe from '../cxelements/cxelements.js';
import * as cxa from '../cxadds/cxadds.js';


export class CXSplitView extends CXDefaultView {

    private _bookingLists: { left:cxe.CXScrollList| null, right:cxe.CXScrollList|null } ={left:null, right:null};
    private _textField:cxe.CXTextBox|null = null; 
    private _leftList:string[][]  =[[]];
    private _rightList:string[][] =[[]];  
    //holds the full table-List
    private _tableList:string[][] =[[]];  
    //index in the table-List
    private _leftListIndex:number[] =[];  
    private _rightListIndex:number[] =[];  
    
    
    constructor(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, is_relative = true, redraw = true) {
        super(ctx, x, y, width, height, is_relative, redraw);
        this._initializeSplitView();
    }
    protected _initializeSplitView(): void{
        const listx = 0.045;
        const listy = 0.15;
        const listh = 1 - 2*listy;
        const listw = 0.5 - 1.5*listx;
        const doredraw = true;
        this._rightList =[];  
        this._leftList =[];
        this._leftListIndex = []; 
        this._rightListIndex =[]; 

        //full tablelist
        //this._leftList = this.Table.List();
        this._tableList =[["1", "Artikel1", "24.40" ],["2","Artikel2","50.50"] ];
        for (let i=0; i<20; i++){
            
            this._tableList.push([ (i+3).toString(),"Artikel" + (i+3).toString(), ((i+1)*6.25).toFixed(2) ]);
        } 
        this._initializeLeftList();
        
        //left scrolllist
        const leftList = new cxe.CXScrollList(this._ctx,listx,listy,listw,listh,this._is_relative,doredraw);
        leftList.attributes = {background_color: "white", border_width: 0.01, border_color: "#808080ff", border_radius: 0.001} ;
        leftList.onSelect = (obj:cxe.CXScrollList,index:number) =>{this._onLeftListClick(obj,index)};
        leftList.list = this._leftList;
        leftList.name = "leftList";
        this._elements.push(leftList);
 
        //right scrolllist
        const rightList = new cxe.CXScrollList(this._ctx,1-leftList.width-leftList.xpos,leftList.ypos,leftList.width,leftList.height,this._is_relative,doredraw);
        rightList.attributes = {background_color: "white", border_width: 0.01, border_color: "#808080ff", border_radius: 0.001} ;
        rightList.onSelect = (obj:cxe.CXScrollList,index:number) =>{this._onRightListClick(obj,index)};
        rightList.list = this._rightList;
        rightList.name = "rightList";
        this._elements.push(rightList);

        //arrow textbox
        const arrw = (rightList.xpos - listx - listw)*0.9;
        const arrh = arrw;
        const arrx = rightList.xpos - (rightList.xpos - (leftList.xpos+leftList.width))/2 - arrw/2;
        const arry = rightList.ypos + rightList.height/2 - arrh/2;
        const arrowtext = new cxe.CXTextBox(this._ctx,arrx,arry,arrw,arrh,this._is_relative,false);
        arrowtext.attributes = {background_color: this.background_color, border_color: this.background_color, text: "\u{21CB}", font_size: 0.99};
        this._elements.push(arrowtext);

        //array of bookinglists
        this._bookingLists ={left:leftList, right:rightList};

        //lines top and bottom
        const lineheight = 0.001;
        const linedistance_y = 0.02;
        const linedistance_x = 0.01;
        
        const topline = new cxe.CXBox(this._ctx,linedistance_x,leftList.ypos-linedistance_y,this.width-2*linedistance_x,lineheight, this._is_relative, false);
        topline.attributes = {background_color: "#808080ff", border_width: 0, border_color: "#808080ff", border_radius: 0} ;
        this._elements.push(topline);
        const bottomline = new cxe.CXBox(this._ctx,linedistance_x,leftList.ypos+ leftList.height +linedistance_y,this.width-2*linedistance_x,lineheight, this._is_relative, false);
        bottomline.attributes = {background_color: "#808080ff", border_width: 0, border_color: "#808080ff", border_radius: 0} ;
        this._elements.push(bottomline);

        
        
        //buttons bottom
        
        const button_x = leftList.xpos;
        const button_height = (this.height - (bottomline.ypos + bottomline.height))*0.6;
        //const button_width = button_height*this.heightpixel/this.widthpixel*4;
        const button_width =0.14;
        const button_y = (bottomline.ypos + bottomline.height) + ((this.height - (bottomline.ypos + bottomline.height)) - button_height)/2;
        const button_distance = 0.015;
        
        
        //return button
        const return_btn = new cxe.CXButton(this._ctx, button_x, button_y, button_width, button_height, this._is_relative, false);
        return_btn.attributes = { ...this._special_func_buttons };
        return_btn.text = '< Zurück';
        return_btn.font_size = 0.4;
        return_btn.onClick = (obj:cxe.CXButton) =>{this._onReturnButtonClick(obj)};
        this._elements.push(return_btn);

        

        //moveall button
        const moveall_btn = new cxe.CXButton(this._ctx, (return_btn.xpos + return_btn.width + button_distance), button_y, button_width, button_height, this._is_relative, false);
        moveall_btn.attributes = { ...this._special_func_buttons };
        moveall_btn.text = 'Alle verschieben';
        moveall_btn.font_size = 0.35;
        moveall_btn.onClick = (obj:cxe.CXButton) =>{this._onMoveAllClick(obj)} ;
        this._elements.push(moveall_btn);

        //check button
        const check_btn = new cxe.CXButton(this._ctx, (rightList.xpos + rightList.width - button_width), button_y, button_width, button_height, this._is_relative, false);
        check_btn.attributes ={ ...this._special_func_buttons };
        check_btn.text = 'Rechnung';
        check_btn.font_size = 0.4;
        check_btn.onClick = (obj:cxe.CXButton) => this._onCheckButtonClick(obj);
        this._elements.push(check_btn);

        //tablebook button
        const table_btn = new cxe.CXButton(this._ctx, (check_btn.xpos - button_width - button_distance), button_y, button_width, button_height, this._is_relative, false);
        table_btn.attributes ={ ...this._special_func_buttons };
        table_btn.text = 'Tisch umbuchen';
        table_btn.font_size = 0.35;
        table_btn.onClick = (obj:cxe.CXButton) => this._onTableButtonClick(obj);
        this._elements.push(table_btn);

        //bar button
        const bar_btn = new cxe.CXButton(this._ctx, (table_btn.xpos - button_width - button_distance), button_y, button_width, button_height, this._is_relative, false);
        bar_btn.attributes ={ ...this._bar_buttons };
        bar_btn.text = 'BAR';
        bar_btn.font_size = 0.4;
        bar_btn.onClick = (obj:cxe.CXButton) => this._onBarButtonClick(obj);
        this._elements.push(bar_btn);


        //numfield
        const num_width = 0.9;
        let num_height = topline.ypos*0.58;
        let num_ypos = (topline.ypos - num_height)/2;
        const num_xpos = rightList.xpos + rightList.width - num_width;
        const num_field = new cxe.CXNumPad(this._ctx, num_xpos, num_ypos, num_width, num_height, this._is_relative, false);
        num_field.buttons_text_block = [['1','2','3','4','5','6','7','8','9','0']];
        num_field.gap = 0.015;
        num_field.font_size = bar_btn.font_size;
        //num_field.buttonAttributes ={...this._numpad_buttons};
        
         
        //First set all values then calculate the optimal width for square buttons
        let opt_width = num_field.calcOptimalWidth();
        if (opt_width<num_width){ 
            
            num_field.xpos=num_field.xpos+num_field.width-opt_width;
            num_field.width=opt_width;
        } 
        num_field.onClick = (obj:cxe.CXNumPad,val:string|null ) => this._onNumFieldChanged(obj,val);
        this._elements.push(num_field);

        //clear button
        const clear_button_width = 200;
        
        const clear_button = new cxe.CXButton(this._ctx, 0, num_ypos, clear_button_width, num_height, this._is_relative, true);
        clear_button.attributes ={...this._special_func_buttons};
        clear_button.text = "C";
        clear_button.font_size = bar_btn.font_size;
        
        
        clear_button.setSquareSize(null);
        clear_button.xpos = num_field.xpos - clear_button.width - num_field.gap*num_field.width;
        clear_button.onClick = (obj:cxe.CXButton) => this._onClearButtonClick(obj);
        this._elements.push(clear_button);

        //textbox
        const text_field_width = clear_button.xpos - leftList.xpos - clear_button.width/2;
        const text_field_height = clear_button.height*0.8;
        const text_field_ypos = clear_button.ypos+(clear_button.height-text_field_height)/2;
        this._textField = new cxe.CXTextBox(this._ctx, leftList.xpos,text_field_ypos,text_field_width,text_field_height,this._is_relative,true);
        this._textField.attributes ={...this._textbox};
        this._elements.push(this._textField);

        leftList.onSelect = (obj:cxe.CXScrollList,index:number) =>{this._onLeftListClick(obj,index)};



    } 

    //callback for left bookinglist
    private _onLeftListClick(obj:cxe.CXScrollList,index:number): void {
        console.debug(`Index:{index}`);
        if (this._bookingLists.left && this._bookingLists.right){ 
            //this._rightList.push(this._leftList[index]);
            //this._leftList.splice(index,1);
            this._modifyLists(index);
            this._bookingLists.left!.list = this._leftList;
            this._bookingLists.right!.list = this._rightList;
            this._bookingLists.left!.draw();
            this._bookingLists.right!.draw();
            //this.draw();
        } 
    } 

    //callback for right bookinglist
    private _onRightListClick(obj:cxe.CXScrollList,index:number): void {
        console.debug(`Index:{index}`);
        if (this._bookingLists.left && this._bookingLists.right){ 
            this._modifyLists(null, index);
            this._bookingLists.left!.list = this._leftList;
            this._bookingLists.right!.list = this._rightList;
            this._bookingLists.left!.draw();
            this._bookingLists.right!.draw();
            //this.draw();
        } 
    } 

    //callback for moveall button
    private _onMoveAllClick(btn:cxe.CXButton): void {
        console.debug(`onMoveAllClick`);
        //move from right to left if leftlist is empty
        if (this._leftListIndex.length == 0) {
            this._leftListIndex = Array.from(this._rightListIndex);
            this._rightListIndex =[];
            this._leftList = Array.from(this._rightList) ;
            this._rightList =[]; 
        } 
        else {
            //move all to right side (default status)
            this._initializeLeftList();
            this._rightList = this._leftList;
            this._rightListIndex = this._leftListIndex;
            this._leftList =[];
            this._leftListIndex=[];  
            
        } 
        this._bookingLists.left!.list = this._leftList;
        this._bookingLists.right!.list = this._rightList;
        this._bookingLists.left!.draw();
        this._bookingLists.right!.draw();
    } 

    //handle the event when the numfield has changed  
    private _onNumFieldChanged(obj:cxe.CXNumPad,currentValue:string|null ): void{
        if (this._textField != null){ 
            if (currentValue != null){
                if ((this._textField.text == "") && (currentValue == "0")){
                    //ignore value
                } 
                else{
                    if (this._textField.text.length>7){ //ignore more vals 
                    } 
                    else {
                        this._textField.text = this._textField.text + currentValue;
                        this._textField.draw();
                    } 
                    
                } 
            } 
        } 
    } 

    private _onClearButtonClick(obj:cxe.CXButton): void{
        if (this._textField != null){
            this._textField.text="";
            this._textField.draw();
        } 
        
    } 

    private _onReturnButtonClick(obj:cxe.CXButton): void{
        
    }

    private _onBarButtonClick(obj:cxe.CXButton): void{
        
    }
    
    private _onTableButtonClick(obj:cxe.CXButton): void{
    
    } 

    private _onCheckButtonClick(obj:cxe.CXButton): void{

    } 

    private _initializeLeftList():void {
        this._leftList = Array.from(this._tableList);
        this._leftListIndex = Array.from({length: this._leftList.length}, (_, index: number) => index);
      
    } 

    

    
    /*
        mofifies the left and right list according to the given index-numbers;
        if left index is null, the right index must be a number;
        if the left index is a number, the right index is not considered
    */
    private _modifyLists(leftIndex:number| null , rightIndex:number| null = null  ) {
        let helpIndex=0;
        
        if (typeof(leftIndex) == 'number') {
            //move from left to right list
            helpIndex = this._leftListIndex[leftIndex];
            this._leftListIndex.splice(leftIndex,1);
            this._leftList.splice(leftIndex,1);
            this._rightListIndex.push(helpIndex);
            this._rightListIndex.sort((a:number, b:number) => {return a-b} );
            this._rightList = this._rightListIndex.map((rindex:number) => {return this._tableList[rindex]});

        } 
        else if (typeof(rightIndex) == 'number') {
            //move from right to left list
            helpIndex = this._rightListIndex[rightIndex];
            this._rightListIndex.splice(rightIndex,1);
            this._rightList.splice(rightIndex,1);
            this._leftListIndex.push(helpIndex);
            this._leftListIndex.sort((a:number, b:number) => {return a-b});
            this._leftList = this._leftListIndex.map((lindex:number) => {return this._tableList[lindex]});
        } 
        else {
            console.warn("leftIndex and rightIndex is null!");
        } 
    } 

    
    //Public callback functions
    /**
     * Callback function to handle return button click 
     * 
     * @param object - the object of the current splitview
     */
    onReturnButtonClick: (object: this) => void = (): void => {
        console.log("Override onReturnButtonClick callback function");
    }
    /**
     * Callback function to handle BAR button click 
     * 
     * @param table - origin table object
     * @param lefttable - the leftside table object
     * @param righttable - the rightside table object
     * @param object - the object of the current splitview
     */
    onBarButtonClick: (object: this, table: cxa.CXTable, lefttable: cxa.CXTable, righttable: cxa.CXTable) => void = (): void => {
        console.log("Override onBarButtonClick callback function");
    }
    /**
     * Callback function to handle table button click 
     * 
     * @param table - origin table object
     * @param lefttable - the leftside table object
     * @param righttable - the rightside table object
     * @param object - the object of the current splitview
     */
    onTableButtonClick: (object: this, table: cxa.CXTable, lefttable: cxa.CXTable, righttable: cxa.CXTable) => void = (): void => {
        console.log("Override onTableButtonClick callback function");
    }
    /**
     * Callback function to handle table button click 
     * 
     * @param table - origin table object
     * @param lefttable - the leftside table object
     * @param righttable - the rightside table object
     * @param object - the object of the current splitview
     */
    onCheckButtonClick: (object: this, table: cxa.CXTable, lefttable: cxa.CXTable, righttable: cxa.CXTable) => void = (): void => {
        console.log("Override onCheckButtonClick callback function");
    }
   
} 