class UIView{constructor(canvas){this.is_active=false;this.canvas='#'+canvas;this.ctx=document.getElementById(canvas).getContext('2d');this.button=new UIButton(this.canvas);this.line=new UILine(this.canvas);this.text=new UIText(this.canvas);this.numpad=new UINumpad(this.canvas);this.list=new UIList(this.canvas);this.arrowbutton=new UIArrowButton(this.canvas);this.textbox=new UITextBox(this.canvas);this.paylist=new UIPayList(this.canvas);this.dragndrop=new UIDragNDrop(this.canvas);this.tableplan=new UITablePlan(this.canvas);this.ui_types=[{type:'Button',object:this.button},{type:'Line',object:this.line},{type:'Text',object:this.text},{type:'Numpad',object:this.numpad},{type:'List',object:this.list},{type:'ArrowButton',object:this.arrowbutton},{type:'TextBox',object:this.textbox},{type:'PayList',object:this.paylist},{type:'DragNDrop',object:this.dragndrop},{type:'TablePlan',object:this.tableplan}];this.onClick=this.onClick.bind(this);this.onMouseUp=this.onMouseUp.bind(this);this.onMouseDown=this.onMouseDown.bind(this);this.onMouseMove=this.onMouseMove.bind(this);$(this.canvas).on('mousedown',this.onMouseDown);$(this.canvas).on('mouseup',this.onMouseUp);$(this.canvas).on('click',this.onClick);$(this.canvas).on('mouseleave',this.onMouseUp);$(this.canvas).on('mouseleave',this.onClick);$(this.canvas).on('mousemove',this.onMouseMove);}
element(name){for(var i in this.ui_types){var obj=this.ui_types[i].object.find(name);if(obj!=null){return obj;}}}
addElement(element_type,options){for(var i in this.ui_types){if(this.ui_types[i].type==element_type){options.type=element_type;this.ui_types[i].object.add(options);return this.ui_types[i].object;}}}
render(){if(this.is_active){for(let i in this.ui_types){this.ui_types[i].object.render(this.ctx);}}
else{return;}}
setActive(state){this.is_active=state;}
onClick(e){if(this.is_active==true){var canvas=$(this.canvas);var x=Math.floor((e.pageX-canvas.offset().left));var y=Math.floor((e.pageY-canvas.offset().top));for(let i in this.ui_types){let ui_type=this.ui_types[i];ui_type.object.onClick(x,y);}}else{return;}}
onMouseUp(e){if(this.is_active==true){var canvas=$(this.canvas);var x=Math.floor((e.pageX-canvas.offset().left));var y=Math.floor((e.pageY-canvas.offset().top));for(let i in this.ui_types){let ui_type=this.ui_types[i];ui_type.object.onMouseUp(x,y);}}else{return;}}
onMouseDown(e){if(this.is_active==true){var canvas=$(this.canvas);var x=Math.floor((e.pageX-canvas.offset().left));var y=Math.floor((e.pageY-canvas.offset().top));for(let i in this.ui_types){let ui_type=this.ui_types[i];ui_type.object.onMouseDown(x,y);}}else{return;}}
onMouseMove(e){if(this.is_active==true){var canvas=$(this.canvas);var x=Math.floor((e.pageX-canvas.offset().left));var y=Math.floor((e.pageY-canvas.offset().top));for(let i in this.ui_types){let ui_type=this.ui_types[i];ui_type.object.onMouseMove(x,y);}}else{return;}}}class UIText{constructor(canvas){this.texts=[];}
add(options){this.texts.push(options);return options;}
render(ctx){for(var i in this.texts){var text=this.texts[i];ctx.font=text.font_size+'px Courier'
ctx.fillStyle=text.foreground;if(!text.displaytext.includes("\n")){ctx.fillText(text.displaytext,text.x,text.y+text.font_size/1.7);}else{var blines=text.displaytext.split("\n");var yoffs=text.y+text.font_size/1.7;var j;for(j=0;j<blines.length;j++){blines[j].replace("\n",'');ctx.fillText(blines[j],text.x,yoffs);yoffs+=text.font_size;}}}}
onClick(x,y){return;}
onMouseDown(x,y){return;}
onMouseUp(x,y){return;}
onMouseMove(x,y){return;}
find(name){return;}}class UIButton{constructor(canvas){this.hovering_on=null;this.buttons=[];this.mouse_down_on=null;}
add(options){this.buttons.push(options);return options;}
render(ctx){for(var i in this.buttons){var button=this.buttons[i];ctx.lineWidth=button.border_width;ctx.font=button.font_size+'px Everson Mono';if(i==this.hovering_on){ctx.strokeStyle=button.hover_border;}
else{ctx.strokeStyle=button.border;}
var grd;if(button.grd_type=='horizontal'){grd=ctx.createLinearGradient(button.x,button.y,button.x+button.width,button.y);}
else if(button.grd_type=='vertical'){grd=ctx.createLinearGradient(button.x,button.y,button.x,button.y+button.height);}
if(button.grd_type){var step_size=1/button.background.length;if(i==this.mouse_down_on){ctx.fillStyle=button.background[button.background.length-1];}
else{for(var j in button.background){grd.addColorStop(step_size*j,button.background[j]);ctx.fillStyle=grd;}}}
if(button.background.length==1){ctx.fillStyle=button.background[0];}
if(!button.border_radius){ctx.fillRect(button.x,button.y,button.width,button.height);ctx.strokeRect(button.x,button.y,button.width,button.height);}else{roundRect(ctx,button.x,button.y,button.width,button.height,button.border_radius,button.border_width);}
ctx.fillStyle=button.foreground;ctx.strokeStyle=button.foreground;if(button.displaytext){if(!button.displaytext.includes("\n")){var text_width=ctx.measureText(button.displaytext).width;if(button.align=='right'){ctx.fillText(button.displaytext,button.x+button.width-text_width-8,button.y+(button.height/2)+button.font_size/3.3);}
else if(button.align=='left'){ctx.fillText(button.displaytext,button.x+8,button.y+(button.height/2)+button.font_size/3.3);}
else{ctx.fillText(button.displaytext,button.x+(button.width-text_width)/2,button.y+(button.height/2)+button.font_size/3.3);}}else{var blines=button.displaytext.split("\n");var yoffs=button.y+((button.height/2)-(9*(blines.length-1)));var j;for(j=0;j<blines.length;j++){blines[j].replace("\n",'');ctx.fillText(blines[j],button.x+8,yoffs);yoffs=yoffs+18;}}}}}
onClick(x,y){for(var i in this.buttons){var button=this.buttons[i];if(button){var startx=button.x;var starty=button.y;var endx=startx+button.width;var endy=starty+button.height;if(x>=startx&&x<=endx&&y>=starty&&y<=endy&&this.mouse_down_on==i){button.callback(button.callbackData);triggerRepaint();}}}
this.mouse_down_on=null;}
onMouseDown(x,y){for(var i in this.buttons){var button=this.buttons[i];var startx=button.x;var starty=button.y;var endx=startx+button.width;var endy=starty+button.height;if(x>=startx&&x<=endx&&y>=starty&&y<=endy){this.mouse_down_on=i;triggerRepaint();return;}}
this.mouse_down_on=-1;return;}
onMouseUp(x,y){return;}
onMouseMove(x,y){for(var i in this.buttons){var button=this.buttons[i];var startx=button.x;var starty=button.y;var endx=startx+button.width;var endy=starty+button.height;if(x>=startx&&x<=endx&&y>=starty&&y<=endy&&(this.mouse_down_on==null||this.mouse_down_on==i)){this.hovering_on=i;triggerRepaint();return;}}
if(this.hovering_on!=null){triggerRepaint();}
this.hovering_on=null;return;}
find(name){return;}
clear(){this.mouse_down_on=null;this.hovering_on=null;this.buttons=[];}}function roundRect(ctx,x,y,w,h,radius,line_width){var r=x+w;var b=y+h;ctx.lineWidth=line_width;ctx.beginPath();ctx.moveTo(x+radius,y);ctx.lineTo(r-radius,y);ctx.quadraticCurveTo(r,y,r,y+radius);ctx.lineTo(r,y+h-radius);ctx.quadraticCurveTo(r,b,r-radius,b);ctx.lineTo(x+radius,b);ctx.quadraticCurveTo(x,b,x,b-radius);ctx.lineTo(x,y+radius);ctx.quadraticCurveTo(x,y,x+radius,y);ctx.fill();if(line_width>0&&line_width!=undefined){ctx.stroke();}}
function rotate(cx,cy,x,y,angle){var radians=(Math.PI/180)*angle,cos=Math.cos(radians),sin=Math.sin(radians),nx=(cos*(x-cx))+(sin*(y-cy))+cx,ny=(cos*(y-cy))-(sin*(x-cx))+cy;return[nx,ny];}
class UILine{constructor(canvas){this.lines=[];}
add(options){this.lines.push(options);return options;}
render(ctx){for(let i in this.lines){let line=this.lines[i];ctx.strokeStyle=line.background;ctx.lineWidth=line.thickness;let x=line.x;let y=line.y;let endx=x+line.width;let endy=y+line.height
ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(endx,endy);ctx.stroke();}}
onClick(x,y){return;}
onMouseDown(x,y){return;}
onMouseUp(x,y){return;}
onMouseMove(x,y){return;}
find(name){return;}}class UIList{constructor(canvas){this.lists=[]
this.button=new UIButton();this.arrowbutton=new UIArrowButton();}
add(options){options.setList=(params)=>{options.articles=params;options.scrollPosition=0;this.createList();}
options.decreaseScrollPosition=(params)=>{options.scrollPosition-=1;this.createList();}
options.increaseScrollPosition=(params)=>{options.scrollPosition+=1;this.createList();}
options.showUpArrow=false;options.showDownArrow=false;this.lists.push(options);return options}
createList(){this.button.clear();this.arrowbutton.clear();for(var i in this.lists){var list=this.lists[i];var max_y_buttons=Math.round(list.height/(list.elementOptions.height+list.elementOptions.gap)-0.49);var max_x_buttons=Math.round((list.width-list.scrollbarwidth)/(list.elementOptions.width+list.elementOptions.gap)-0.49);for(var j in list.articles){var button_x;var button_y;var article=list.articles[j];var button={...article,...list.elementOptions};var max_buttons=max_x_buttons*max_y_buttons;var article_index=j-max_buttons*list.scrollPosition;var[x,y]=this.getArticlePosition(max_x_buttons,article_index);if(y<max_y_buttons&&y>=0){button_x=list.x+x*(button.width+button.gap);button_y=list.y+y*(button.height+button.gap);button.x=button_x;button.y=button_y;this.button.add(button);}}
if(max_buttons*(list.scrollPosition+1)<list.articles.length){var scroll_x=list.x+list.width-list.scrollbarwidth;var scroll_y=list.y+list.height-list.scrollbarwidth;this.arrowbutton.add({x:scroll_x,y:scroll_y,width:list.scrollbarwidth,height:list.scrollbarwidth,direction:'down',background:['#ffffff'],foreground:'#000000',border:'#000000',border_width:3,hover_border:'#000000',callback:list.increaseScrollPosition});}
if(list.scrollPosition!=0){var scroll_x=list.x+list.width-list.scrollbarwidth;var scroll_y=list.y;this.arrowbutton.add({x:scroll_x,y:scroll_y,width:list.scrollbarwidth,height:list.scrollbarwidth,direction:'up',background:['#ffffff'],foreground:'#000000',border:'#000000',border_width:3,hover_border:'#000000',callback:list.decreaseScrollPosition});}}
}
getArticlePosition(max_x_buttons,article_index){var x=(article_index%max_x_buttons)
var y=Math.round((article_index/max_x_buttons)-0.49);return[x,y];}
render(ctx){this.button.render(ctx);this.arrowbutton.render(ctx);}
onClick(x,y){this.button.onClick(x,y);this.arrowbutton.onClick(x,y);}
onMouseDown(x,y){this.button.onMouseDown(x,y);this.arrowbutton.onMouseDown(x,y);}
onMouseUp(x,y){this.button.onMouseUp(x,y);this.arrowbutton.onMouseUp(x,y);}
onMouseMove(x,y){this.button.onMouseMove(x,y);this.arrowbutton.onMouseMove(x,y);}
find(name){for(var i in this.lists){var list=this.lists[i];if(list.name==name){return list;}}}}class UINumpad{constructor(canvas){this.button=new UIButton();this.numpads=[];}
add(options){this.numpads.push(options);var keyvalues=[['+/-','ZWS','⌫'],['7','8','9'],['4','5','6'],['1','2','3'],['x','0',',']];if(!options.show_keys.x){keyvalues[4][0]=null;}
if(!options.show_keys.ZWS){keyvalues[0][1]=null;}
var button_height=options.height/keyvalues.length-options.gap;var button_width=options.width/keyvalues[0].length-options.gap;for(var buttons_y=0;buttons_y<keyvalues.length;buttons_y++){var position_y=options.y+(button_height+options.gap)*buttons_y;for(var buttons_x=0;buttons_x<keyvalues[0].length;buttons_x++){if(keyvalues[buttons_y][buttons_x]!=null){var position_x=options.x+(button_width+options.gap)*buttons_x;var button={displaytext:keyvalues[buttons_y][buttons_x],x:position_x,y:position_y,width:button_width,height:button_height,type:'Button',callbackData:{key:options.callbackData.key,value:keyvalues[buttons_y][buttons_x]}};this.button.add(Object.assign({},options,button));}}}
return options;}
render(ctx){this.button.render(ctx);}
onClick(x,y){this.button.onClick(x,y);}
onMouseDown(x,y){this.button.onMouseDown(x,y);}
onMouseUp(x,y){this.button.onMouseUp(x,y);}
onMouseMove(x,y){this.button.onMouseMove(x,y);}
find(name){return;}
clear(){this.numpads=[];this.button.clear();}}class UIArrowButton{constructor(canvas){this.arrowbuttons=[];this.button=new UIButton();}
add(options){var point1_x;var point1_y;var point2_x;var point2_y;var point3_x;var point3_y;if(options.direction=='down'){point1_x=0;point1_y=0;point2_x=options.height;point2_y=0;point3_x=options.height/2;point3_y=options.height;}else if(options.direction=='up'){point1_x=0;point1_y=options.height;point2_x=options.height;point2_y=options.height;point3_x=options.height/2;point3_y=0;}else if(direction=='right'){point1_x=0;point1_y=0;point2_x=options.height;point2_y=options.height/2;point3_x=0;point3_y=options.height;}else if(direction=='left'){point1_x=options.height;point1_y=0;point2_x=options.height;point2_y=options.height;point3_x=0;point3_y=options.height/2;}
this.arrowbuttons.push({point1_x:point1_x,point1_y:point1_y,point2_x:point2_x,point2_y:point2_y,point3_x:point3_x,point3_y:point3_y,x:options.x,y:options.y,a_x:options.x+options.width/2-options.height/2,})
this.button.add(options);return options;}
render(ctx){this.button.render(ctx);for(var i in this.arrowbuttons){var arrowbutton=this.arrowbuttons[i];ctx.beginPath();ctx.moveTo(arrowbutton.a_x+arrowbutton.point1_x,arrowbutton.y+arrowbutton.point1_y);ctx.lineTo(arrowbutton.a_x+arrowbutton.point2_x,arrowbutton.y+arrowbutton.point2_y);ctx.lineTo(arrowbutton.a_x+arrowbutton.point3_x,arrowbutton.y+arrowbutton.point3_y);ctx.fill();}}
onClick(x,y){this.button.onClick(x,y);}
onMouseDown(x,y){this.button.onMouseDown(x,y);}
onMouseUp(x,y){this.button.onMouseUp(x,y);}
onMouseMove(x,y){this.button.onMouseMove(x,y);}
find(name){return;}
clear(){this.arrowbuttons=[];this.button.clear();}}class UITextBox{constructor(canvas){this.textboxes=[];this.canvas=canvas;}
add(options){console.log(options.displaytext)
options.setText=(params)=>{options.displaytext=params;}
this.textboxes.push(options);return options;}
render(ctx){for(var i in this.textboxes){var textbox=this.textboxes[i];ctx.font=textbox.font_size+'px Courier';ctx.save();ctx.clearRect(0,0,this.canvas.width,this.canvas.height);ctx.translate(textbox.center_x,textbox.center_y);ctx.rotate(textbox.angle*Math.PI/180);ctx.translate(-textbox.center_x,-textbox.center_y);ctx.strokeStyle=textbox.border;ctx.lineWidth=textbox.border_width;var grd;if(textbox.grd_type=='horizontal'){grd=ctx.createLinearGradient(textbox.x,textbox.y,textbox.x+textbox.width,textbox.y);}
else if(textbox.grd_type=='vertical'){grd=ctx.createLinearGradient(textbox.x,textbox.y,textbox.x,textbox.y+textbox.height);}
if(textbox.grd_type){var step_size=1/textbox.background.length;for(var j in textbox.background){grd.addColorStop(step_size*j,textbox.background[j]);ctx.fillStyle=grd;}}
if(textbox.background.length==1){ctx.fillStyle=textbox.background[0];}
if(!textbox.border_radius){ctx.fillRect(textbox.x,textbox.y,textbox.width,textbox.height);if(textbox.border_width!=0&&textbox.border_width!=undefined){ctx.strokeRect(textbox.x,textbox.y,textbox.width,textbox.height);}}else{roundRect(ctx,textbox.x,textbox.y,textbox.width,textbox.height,textbox.border_radius,textbox.border_width);}
ctx.restore();ctx.fillStyle=textbox.foreground;ctx.strokeStyle=textbox.foreground;if(textbox.displaytext){if(!textbox.displaytext.includes("\n")){var text_width=ctx.measureText(textbox.displaytext).width;if(textbox.align=='right'){ctx.fillText(textbox.displaytext,textbox.x+textbox.width-text_width-8,textbox.y+(textbox.height/2)+textbox.font_size/3.3);}
else if(textbox.align=='left'){ctx.fillText(textbox.displaytext,textbox.x+8,textbox.y+(textbox.height/2)+textbox.font_size/3.3);}
else{ctx.fillText(textbox.displaytext,textbox.x+(textbox.width-text_width)/2,textbox.y+(textbox.height/2)+textbox.font_size/3.3);}}else{var blines=textbox.displaytext.split("\n");var yoffs=textbox.y+((textbox.height/2)-(9*(blines.length-1)));for(var j=0;j<blines.length;j++){if(textbox.align=='right'){blines[j].replace("\n",'');var text_width=ctx.measureText(blines[j]).width;ctx.fillText(blines[j],textbox.x+textbox.width-text_width-8,yoffs);}
else{blines[j].replace("\n",'');ctx.fillText(blines[j],textbox.x+8,yoffs);}
yoffs=yoffs+18;}}}}}
onClick(x,y){return;}
onMouseDown(x,y){return;}
onMouseUp(x,y){return;}
onMouseMove(x,y){return;}
find(name){for(var i in this.textboxes){var textbox=this.textboxes[i];if(textbox.name==name){return textbox;}}}
clear(){this.textboxes=[];}}class UIPayList{constructor(canvass){this.arrowbutton=new UIArrowButton();this.paylists=[];this.listitem=new UIListItem();}
max_items(options){}
add(options){options.scrollposition=0;options.list=[];options.max_paylist_items=Math.round((options.height-(options.pagescrollbuttonheight+5))/options.elementOptions.height-0.49);options.scrollbarsize=options.height-options.pagescrollbuttonheight-2*options.scrollbarwidth-options.border_width;options.scrollbar_y=options.scrollbarwidth+options.border_width/2;options.mousedown_scrollbar_y=null;options.setList=(params)=>{options.list=params;if(options.list.length>options.max_paylist_items){options.scrollposition=options.list.length-options.max_paylist_items;}
else if(options.list.length<options.max_paylist_items){options.scrollposition=0;}
if(options.list.length<=options.selectedID){options.selectedID=null;}
this.update()
return;}
options.deleteSelected=()=>{if(options.selectedID!=null){var index=options.getSelectedItemIndex();options.list.splice(index,1);options.selectedID=null;options.setScrollPosition(options.scrollposition-1);this.update();}}
options.getList=()=>{return options.list;}
options.previousPage=()=>{if(options.max_paylist_items<options.list.length){if(options.scrollposition-options.max_paylist_items>0){options.scrollposition-=options.max_paylist_items;this.update();}
else{options.scrollposition=0
this.update();}}
return;}
options.nextPage=()=>{if(options.max_paylist_items<options.list.length){var nextitem=options.scrollposition+2*options.max_paylist_items;if(nextitem<=options.list.length){options.scrollposition+=options.max_paylist_items;this.update();}
else{options.scrollposition=options.list.length-options.max_paylist_items;this.update();}}
return;}
options.scrollup=()=>{if(options.scrollposition>0){options.scrollposition-=1;this.update();}
return;}
options.scrolldown=()=>{var nextitem=options.scrollposition+options.max_paylist_items+1;if(nextitem<=options.list.length){options.scrollposition+=1;this.update();}
return;}
options.setSelected=(id)=>{options.selectedID=id;this.update();return;}
options.getSelectedItemIndex=()=>{return options.selectedID;}
options.setScrollPosition=(position)=>{if(options.max_paylist_items<options.list.length){if(position<=options.list.length-options.max_paylist_items&&position>0){options.scrollposition=position;this.update();}
else if(position>options.list.length-options.max_paylist_items){options.scrollposition=options.list.length-options.max_paylist_items;this.update();}
else if(position<0){options.scrollposition=0;this.update();}}}
this.arrowbutton.add({x:options.x+options.width-options.scrollbarwidth,y:options.y,width:options.scrollbarwidth,height:options.scrollbarwidth,direction:'up',background:options.background,foreground:options.foreground,border:options.border,border_width:options.border_width,hover_border:'#000000',callback:options.scrollup,hover_border:options.hover_border});this.arrowbutton.add({x:options.x+options.width-options.scrollbarwidth,y:options.y+options.height-options.scrollbarwidth-options.pagescrollbuttonheight,width:options.scrollbarwidth,height:options.scrollbarwidth,direction:'down',background:options.background,foreground:options.foreground,border:options.border,border_width:options.border_width,hover_border:'#000000',callback:options.scrolldown,hover_border:options.hover_border});this.arrowbutton.add({x:options.x,y:options.y+options.height-options.pagescrollbuttonheight+5,width:options.width/2-2,height:options.pagescrollbuttonheight,direction:'up',background:options.background,foreground:options.foreground,border:options.border,border_width:options.border_width,hover_border:'#000000',callback:options.previousPage,hover_border:options.hover_border});this.arrowbutton.add({x:options.x+options.width/2+2,y:options.y+options.height-options.pagescrollbuttonheight+5,width:options.width/2-2,height:options.pagescrollbuttonheight,direction:'down',background:options.background,foreground:options.foreground,border:options.border,border_width:options.border_width,hover_border:'#000000',callback:options.nextPage,hover_border:options.hover_border});this.paylists.push(options);return options;}
update(){this.listitem.clear()
for(var i in this.paylists){var paylist=this.paylists[i];var x=paylist.x;var font_size=paylist.elementOptions.font_size;var selectedBackground=paylist.elementOptions.selectedBackground;var foreground=paylist.foreground;var width=paylist.width-paylist.scrollbarwidth;var max_scrollbarheight=paylist.height-paylist.pagescrollbuttonheight-2*paylist.scrollbarwidth-paylist.border_width;paylist.scrollbarsize=this.getScrollbarSize(paylist.max_paylist_items,paylist.list.length)*max_scrollbarheight;paylist.scrollbar_y=(max_scrollbarheight-paylist.scrollbarsize)*(paylist.scrollposition/(paylist.list.length-paylist.max_paylist_items))+paylist.scrollbarwidth+paylist.border_width/2;if(!paylist.scrollbar_y){paylist.scrollbar_y=paylist.scrollbarwidth+paylist.border_width/2}
for(var j in paylist.list){var index=j-paylist.scrollposition;if(index<paylist.max_paylist_items&&index>=0){var item=paylist.list[j];var y=paylist.y+paylist.elementOptions.height*index;this.listitem.add({...{x:x,y:y,width:width,height:paylist.elementOptions.height,font_size:font_size,selected:paylist.selectedID,border_width:paylist.border_width,selectedBackground:selectedBackground,foreground:foreground,callback:paylist.setSelected,id:j},...item});}}}
triggerRepaint();}
getScrollbarSize(max_paylist_items,list_lenght){var scrollbarsize=(1/(list_lenght/max_paylist_items));if(scrollbarsize>1){scrollbarsize=1;}
return scrollbarsize;}
render(ctx){for(var i in this.paylists){var paylist=this.paylists[i];ctx.font=paylist.font_size+'px Courier';ctx.strokeStyle=paylist.border;var grd;if(paylist.grd_type=='horizontal'){grd=ctx.createLinearGradient(paylist.x,paylist.y,paylist.x+paylist.width,paylist.y);}
else if(paylist.grd_type=='vertical'){grd=ctx.createLinearGradient(paylist.x,paylist.y,paylist.x,paylist.y+paylist.height-paylist.pagescrollbuttonheight);}
if(paylist.grd_type){var step_size=1/paylist.background.length;for(var j in paylist.background){grd.addColorStop(step_size*j,paylist.background[j]);ctx.fillStyle=grd;}}
if(paylist.background.length==1){ctx.fillStyle=paylist.background[0];}
if(!paylist.border_radius){ctx.fillRect(paylist.x,paylist.y,paylist.width,paylist.height-paylist.pagescrollbuttonheight);ctx.strokeRect(paylist.x,paylist.y,paylist.width,paylist.height-paylist.pagescrollbuttonheight);}else{roundRect(ctx,paylist.x,paylist.y,paylist.width,paylist.height-paylist.pagescrollbuttonheight,paylist.border_radius,paylist.border_width);}
ctx.fillStyle=paylist.scrollbarbackground;ctx.fillRect(paylist.x+paylist.width-paylist.scrollbarwidth-paylist.border_width/2,paylist.y+paylist.scrollbarwidth,paylist.scrollbarwidth+paylist.border_width/2,paylist.height-paylist.pagescrollbuttonheight-paylist.scrollbarwidth);ctx.fillStyle=paylist.foreground;ctx.fillRect(paylist.x+paylist.width-paylist.scrollbarwidth-paylist.border_width/2,paylist.y+paylist.scrollbar_y,paylist.scrollbarwidth+paylist.border_width/2,paylist.scrollbarsize);}
this.arrowbutton.render(ctx);this.listitem.render(ctx);}
onClick(x,y){this.arrowbutton.onClick(x,y);this.listitem.onClick(x,y);return;}
onMouseDown(x,y){this.arrowbutton.onMouseDown(x,y);this.listitem.onMouseDown(x,y);for(var i in this.paylists){var paylist=this.paylists[i];var startx=paylist.x+paylist.width-paylist.scrollbarwidth-paylist.border_width/2;var starty=paylist.y+paylist.scrollbarwidth;var endx=paylist.x+paylist.width+paylist.scrollbarwidth+paylist.border_width/2;var endy=paylist.y+paylist.height-paylist.pagescrollbuttonheight-paylist.scrollbarwidth;if(x>=startx&&x<=endx&&y>=starty&&y<=endy){var top_scrollbar=paylist.y+paylist.scrollbar_y;var below_scrollbar=top_scrollbar+paylist.scrollbarsize;starty=paylist.y+paylist.scrollbar_y;endy=starty+paylist.scrollbarsize;if(x>=startx&&x<=endx&&y>=starty&&y<=endy){paylist.mousedown_scrollbar_y=y-starty;}
else if(y<top_scrollbar){paylist.previousPage();}
else if(y>below_scrollbar){paylist.nextPage();}
return;}}
return;}
onMouseUp(x,y){this.arrowbutton.onMouseUp(x,y);this.listitem.onMouseUp(x,y);for(var i in this.paylists){var paylist=this.paylists[i];paylist.mousedown_scrollbar_y=null;}
return;}
onMouseMove(x,y){this.arrowbutton.onMouseMove(x,y);this.listitem.onMouseMove(x,y);for(var i in this.paylists){var paylist=this.paylists[i];if(paylist.mousedown_scrollbar_y!=null){var scroll_y=(y-paylist.mousedown_scrollbar_y)-(paylist.y+paylist.scrollbarwidth)
var max_scrollbarheight=paylist.height-paylist.pagescrollbuttonheight-2*paylist.scrollbarwidth-paylist.border_width;var empty_scrollbar_space=max_scrollbarheight-paylist.scrollbarsize;var scroll_position=Math.round(((paylist.list.length-paylist.max_paylist_items)/empty_scrollbar_space)*scroll_y);paylist.setScrollPosition(scroll_position);triggerRepaint();console.log('repaint');}}
return;}
find(name){for(var i in this.paylists){var paylist=this.paylists[i];if(paylist.name==name){return paylist;}}}}class UIListItem{constructor(canvas){this.listitems=[];this.mouse_down_on=null;}
add(options){this.listitems.push(options);return options;}
render(ctx){for(var i in this.listitems){var listitem=this.listitems[i];ctx.fillStyle=listitem.selectedBackground;var selected=listitem.selected;if(selected==listitem.id){ctx.fillRect(listitem.x+listitem.border_width/1.8,listitem.y+listitem.border_width/2,listitem.width-listitem.border_width*1.2,listitem.height);}
var type=listitem.type;ctx.fillStyle=listitem.foreground;ctx.strokeStyle=listitem.foreground;ctx.font=listitem.font_size+'px Courier';for(var j in listitem.lineitem){var lineitem=listitem.lineitem[j];if(type=="text"){if(lineitem.align=='right'){var x=listitem.x+listitem.width*lineitem.location
ctx.fillText(lineitem.displaytext,x,listitem.y+listitem.height/2+listitem.font_size/2.7);}
else if(lineitem.align=='left'){var x=listitem.x+listitem.width*lineitem.location-ctx.measureText(lineitem.displaytext).width
ctx.fillText(lineitem.displaytext,x,listitem.y+listitem.height/2+listitem.font_size/2.7);}
else if(lineitem.align=='center'){}}
if(type=="textline"){var text_width=ctx.measureText(lineitem.displaytext).width;var length=lineitem.end-lineitem.start;var linewidth=listitem.width*length;var text='';for(var k=0;k<=Math.round(linewidth/text_width-0.49);k++){text+=lineitem.displaytext;}
var x=listitem.x+listitem.width*lineitem.start;ctx.fillText(text,x,listitem.y+listitem.height/2+listitem.font_size/2.7);}}}}
onClick(x,y){for(var i in this.listitems){var listitem=this.listitems[i];var startx=listitem.x+listitem.border_width/1.8;var starty=listitem.y+listitem.border_width/2;var endx=listitem.width-listitem.border_width*1.2+startx;var endy=starty+listitem.height;if(x>=startx&&x<=endx&&y>=starty&&y<=endy&&this.mouse_down_on==i){listitem.callback(listitem.id);}}
this.mouse_down_on=null;}
onMouseDown(x,y){for(var i in this.listitems){var listitem=this.listitems[i];var startx=listitem.x+listitem.border_width/1.8;var starty=listitem.y+listitem.border_width/2;var endx=listitem.width-listitem.border_width*1.2+startx;var endy=starty+listitem.height;if(x>=startx&&x<=endx&&y>=starty&&y<=endy){this.mouse_down_on=i;}}}
onMouseUp(x,y){return;}
onMouseMove(x,y){return;}
find(name){return;}
clear(){this.listitems=[];}}class UIDragNDrop{constructor(canvas){this.textbox=new UITextBox(canvas);this.circle=new UICircle(canvas);this.dragndrops=[];this.mouse_down=false;this.mouse_down_x=null;this.mouse_down_y=null;this.box_size=22;this.box_size_half=this.box_size/2;this.canvas=canvas;}
add(options){options.selected=false;options.resizeable=false;options.center_x=options.x+options.width/2;options.center_y=options.y+options.height/2;options.resizedirection='';options.changed=true;options.mouse_down_action='';options.moveable=false;options.change=()=>{options.changed=true;this.changeHandler(options);}
this.dragndrops.push(options);if(options.type=='circle'){this.circle.add(options);}
else{this.textbox.add(options);}
return options;}
render(ctx){for(var j in this.dragndrops){var dragndrop=this.dragndrops[j];if(dragndrop.type=='circle'){this.circle.circles=[dragndrop];this.circle.render(ctx);}
else{this.textbox.textboxes=[dragndrop];this.textbox.render(ctx);}}
for(var i in this.dragndrops){var dragndrop=this.dragndrops[i];if(dragndrop.editable==true&&dragndrop.selected==true){ctx.save();ctx.clearRect(0,0,this.canvas.width,this.canvas.height);ctx.translate(dragndrop.center_x,dragndrop.center_y);ctx.rotate(dragndrop.angle*Math.PI/180);ctx.translate(-dragndrop.center_x,-dragndrop.center_y)
ctx.strokeStyle='black';ctx.lineWidth=dragndrop.border_width*1.5;ctx.fillStyle='black';ctx.beginPath();ctx.rect(dragndrop.x,dragndrop.y,dragndrop.width,dragndrop.height);ctx.stroke();ctx.strokeStyle='white';ctx.lineWidth=1;ctx.beginPath();ctx.rect(dragndrop.x-this.box_size_half,dragndrop.y-this.box_size_half,this.box_size,this.box_size);ctx.rect(dragndrop.x-this.box_size_half,dragndrop.y+dragndrop.height-this.box_size_half,this.box_size,this.box_size);ctx.rect(dragndrop.x+dragndrop.width-this.box_size_half,dragndrop.y-this.box_size_half,this.box_size,this.box_size);ctx.rect(dragndrop.x+dragndrop.width-this.box_size_half,dragndrop.y+dragndrop.height-this.box_size_half,this.box_size,this.box_size);ctx.fill();ctx.beginPath();ctx.arc(dragndrop.x+dragndrop.width/2,dragndrop.y-this.box_size_half*3,this.box_size_half,0,2*Math.PI);ctx.fill();ctx.beginPath();ctx.strokeStyle='black';ctx.moveTo(dragndrop.x+dragndrop.width/2,dragndrop.y);ctx.lineTo(dragndrop.x+dragndrop.width/2,dragndrop.y-this.box_size_half*3);ctx.stroke();ctx.strokeStyle='white';ctx.beginPath();if(dragndrop.width>2*this.box_size){ctx.rect(dragndrop.x+dragndrop.width/2-this.box_size_half,dragndrop.y-this.box_size_half,this.box_size,this.box_size);ctx.rect(dragndrop.x+dragndrop.width/2-this.box_size_half,dragndrop.y+dragndrop.height-this.box_size_half,this.box_size,this.box_size);}
if(dragndrop.height>2*this.box_size){ctx.rect(dragndrop.x-this.box_size_half,dragndrop.y+dragndrop.height/2-this.box_size_half,this.box_size,this.box_size);ctx.rect(dragndrop.x+dragndrop.width-this.box_size_half,dragndrop.y+dragndrop.height/2-this.box_size_half,this.box_size,this.box_size);}
ctx.stroke();ctx.fill();ctx.restore();}}}
setEditable(group_id,state){for(var i in this.dragndrops){var dragndrop=this.dragndrops[i];if(dragndrop.group_id==group_id){dragndrop.editable=state;if(!state){dragndrop.selected=false;}}}}
deleteSelected(group_id){this.circle.clear();this.textbox.clear();for(var i in this.dragndrops){var dragndrop=this.dragndrops[i];if(dragndrop.selected&&dragndrop.group_id==group_id){this.dragndrops.splice(i,1);var undoable=[]
for(var j in this.dragndrops){if(dragndrop.type=='circle'){this.circle.add({...dragndrop});}
else{this.textbox.add({...dragndrop});}
if(group_id==this.dragndrops[j].group_id){undoable.push({...this.dragndrops[j]});}}
dragndrop.callback(undoable);}}}
replaceElementsByGropID(group_id,elementList){var new_dragndrops=[];var editable=null;this.circle.clear();this.textbox.clear();for(var i in this.dragndrops){var dragndrop=this.dragndrops[i];if(dragndrop.group_id!=group_id){new_dragndrops.push({...dragndrop});if(dragndrop.type=='circle'){this.circle.add({...dragndrop});}
else{this.textbox.add({...dragndrop});}}
else if(editable==null){editable=dragndrop.editable;}}
for(var i in elementList){var dragndrop=elementList[i];dragndrop.editable=editable;new_dragndrops.push({...dragndrop});if(dragndrop.type=='circle'){this.circle.add({...dragndrop});}
else{this.textbox.add({...dragndrop});}}
this.dragndrops=new_dragndrops;}
onClick(x,y){return;}
onMouseDown(x,y){for(var i=this.dragndrops.length-1;i>=0;i--){var dragndrop=this.dragndrops[i];var[nx,ny]=rotate(dragndrop.center_x,dragndrop.center_y,x,y,dragndrop.angle);[dragndrop.center_x,dragndrop.center_y]=rotate(dragndrop.center_x,dragndrop.center_y,dragndrop.x+dragndrop.width/2,dragndrop.y+dragndrop.height/2,-dragndrop.angle);dragndrop.x=dragndrop.center_x-dragndrop.width/2;dragndrop.y=dragndrop.center_y-dragndrop.height/2;var startx=dragndrop.x;var starty=dragndrop.y;var endx=startx+dragndrop.width;var endy=starty+dragndrop.height;if(dragndrop.resizeable&&dragndrop.editable&&dragndrop.selected){this.mouse_down=true;this.array_move(this.dragndrops,i,this.dragndrops.length-1);this.mouse_down_x=x-startx;this.mouse_down_y=y-starty;dragndrop.mouse_down_action=dragndrop.resizedirection;[dragndrop.center_x,dragndrop.center_y]=rotate(dragndrop.center_x,dragndrop.center_y,dragndrop.x+dragndrop.width/2,dragndrop.y+dragndrop.height/2,-dragndrop.angle);dragndrop.x=dragndrop.center_x-dragndrop.width/2;dragndrop.y=dragndrop.center_y-dragndrop.height/2;return;}
else{dragndrop.mouse_down_action='';}
if(nx>=startx&&nx<=endx&&ny>=starty&&ny<=endy){dragndrop.selected=true;dragndrop.isSelected(dragndrop);var g_id=dragndrop.group_id;for(var j=this.dragndrops.length-1;j>=0;j--){var s_dragndrop=this.dragndrops[j];if(s_dragndrop.group_id==g_id&&j!=i){s_dragndrop.selected=false;}}
this.mouse_down=true;this.array_move(this.dragndrops,i,this.dragndrops.length-1);this.mouse_down_x=x-startx;this.mouse_down_y=y-starty;triggerRepaint();return;}}
for(var i=this.dragndrops.length-1;i>=0;i--){var dragndrop=this.dragndrops[i];if(x>dragndrop.contain_x&&x<dragndrop.contain_x+dragndrop.contain_width&&y>dragndrop.contain_y&&y<dragndrop.contain_y+dragndrop.contain_height){dragndrop.selected=false;dragndrop.isSelected(null);}}
triggerRepaint();return;}
changeHandler(dragndrop){if(dragndrop.changed){var group_id=dragndrop.group_id;dragndrop.changed=false;var undoable=[]
for(var j in this.dragndrops){if(group_id==this.dragndrops[j].group_id){undoable.push({...this.dragndrops[j]});}}
dragndrop.callback(undoable);}}
onMouseUp(x,y){for(var i in this.dragndrops){var dragndrop=this.dragndrops[i];[dragndrop.center_x,dragndrop.center_y]=rotate(dragndrop.center_x,dragndrop.center_y,dragndrop.x+dragndrop.width/2,dragndrop.y+dragndrop.height/2,-dragndrop.angle);dragndrop.x=dragndrop.center_x-dragndrop.width/2;dragndrop.y=dragndrop.center_y-dragndrop.height/2;this.changeHandler(dragndrop);dragndrop.mouse_down_action='';}
this.mouse_down=false;this.mouse_down_x=null;this.mouse_down_y=null;}
array_move(arr,old_index,new_index){if(new_index>=arr.length){var k=new_index-arr.length+1;while(k--){arr.push(undefined);}}
arr.splice(new_index,0,arr.splice(old_index,1)[0]);return arr;};setCursorAtLocation(mouse_x,mouse_y,x,y,width,height,cursor_type,object){var x1=x+width;var y1=y+height;if(mouse_x>=x&&mouse_x<=x1&&mouse_y>=y&&mouse_y<=y1){$(this.canvas).css('cursor',cursor_type);object.resizeable=true;object.resizedirection=cursor_type;return;}}
calculateCornerPositions(x,y,width,height,angle,sort_x,sort_y){var[corners_x,corners_y]=this.calculateUnsortedCornerPositions(x,y,width,height,angle);if(sort_x||sort_x==undefined){corners_x.sort(function(a,b){return a-b});}
if(sort_y||sort_y==undefined){corners_y.sort(function(a,b){return a-b});}
return[corners_x,corners_y];}
calculateUnsortedCornerPositions(x,y,width,height,angle){var center_x=x+width/2
var center_y=y+height/2
var corners_x=[rotate(center_x,center_y,x,y,angle)[0],rotate(center_x,center_y,x+width,y,angle)[0],rotate(center_x,center_y,x+width,y+height,angle)[0],rotate(center_x,center_y,x,y+height,angle)[0]];var corners_y=[rotate(center_x,center_y,x+width,y+height,angle)[1],rotate(center_x,center_y,x,y+height,angle)[1],rotate(center_x,center_y,x,y,angle)[1],rotate(center_x,center_y,x+width,y,angle)[1]];return[corners_x,corners_y];}
onMouseMove(x,y){if(this.mouse_down){var dragndrop=this.dragndrops[this.dragndrops.length-1];var[nx,ny]=rotate(dragndrop.center_x,dragndrop.center_y,x,y,dragndrop.angle);if(dragndrop.mouse_down_action!=''&&dragndrop.editable==true&&dragndrop.selected){$(this.canvas).css('cursor',dragndrop.mouse_down_action);var new_height=dragndrop.height;var new_width=dragndrop.width;var new_x=dragndrop.x;var new_y=dragndrop.y;if(dragndrop.mouse_down_action=='s-resize'||dragndrop.mouse_down_action=='se-resize'||dragndrop.mouse_down_action=='sw-resize'){new_height=ny-dragndrop.y;if(new_height<=this.box_size+2){new_height=this.box_size+2;}}
if(dragndrop.mouse_down_action=='e-resize'||dragndrop.mouse_down_action=='ne-resize'||dragndrop.mouse_down_action=='se-resize'){new_width=nx-dragndrop.x;if(new_width<=this.box_size+2){new_width=this.box_size+2;}}
if(dragndrop.mouse_down_action=='n-resize'||dragndrop.mouse_down_action=='ne-resize'||dragndrop.mouse_down_action=='nw-resize'){new_y=ny;new_height=dragndrop.height+(dragndrop.y-ny);if(new_height<=this.box_size+2){new_y=new_y-(this.box_size+2-new_height);new_height=this.box_size+2;}}
if(dragndrop.mouse_down_action=='w-resize'||dragndrop.mouse_down_action=='nw-resize'||dragndrop.mouse_down_action=='sw-resize'){new_x=nx;new_width=dragndrop.width+(dragndrop.x-nx);if(new_width<=this.box_size+2){new_x=new_x-(this.box_size+2-new_width);new_width=this.box_size+2;}}
var dragndropnoref={...this.dragndrops[this.dragndrops.length-1]};dragndropnoref.width=new_width;dragndropnoref.height=new_height;dragndropnoref.x=new_x;dragndropnoref.y=new_y;[dragndropnoref.center_x,dragndropnoref.center_y]=rotate(dragndropnoref.center_x,dragndropnoref.center_y,dragndropnoref.x+dragndropnoref.width/2,dragndropnoref.y+dragndropnoref.height/2,-dragndropnoref.angle);dragndropnoref.x=dragndropnoref.center_x-dragndropnoref.width/2;dragndropnoref.y=dragndropnoref.center_y-dragndropnoref.height/2;if(dragndropnoref.mouse_down_action=='crosshair'){var mouse_relative_center_x=x-dragndropnoref.center_x;var mouse_relative_center_y=y-dragndropnoref.center_y;var result=Math.atan2(mouse_relative_center_x,mouse_relative_center_y);var angle=-180-(result*180)/Math.PI;dragndropnoref.angle=angle;}
var[x_corners,y_corners]=this.calculateCornerPositions(dragndropnoref.x,dragndropnoref.y,dragndropnoref.width,dragndropnoref.height,dragndropnoref.angle);var max_y_corner=y_corners[3];var min_y_corner=y_corners[0];var max_x_corner=x_corners[3];var min_x_corner=x_corners[0];if(max_y_corner<=dragndrop.contain_y+dragndrop.contain_height&&min_y_corner>=dragndrop.contain_y&&min_x_corner>=dragndrop.contain_x&&max_x_corner<=dragndrop.contain_x+dragndrop.contain_width){dragndrop.changed=true;dragndrop.width=new_width;dragndrop.height=new_height;dragndrop.x=new_x;dragndrop.y=new_y;[dragndrop.center_x,dragndrop.center_y]=rotate(dragndrop.center_x,dragndrop.center_y,dragndrop.x+dragndrop.width/2,dragndrop.y+dragndrop.height/2,-dragndrop.angle);dragndrop.x=dragndrop.center_x-dragndrop.width/2;dragndrop.y=dragndrop.center_y-dragndrop.height/2;if(dragndrop.mouse_down_action=='crosshair'){var mouse_relative_center_x=x-dragndrop.center_x;var mouse_relative_center_y=y-dragndrop.center_y;var result=Math.atan2(mouse_relative_center_x,mouse_relative_center_y);var angle=-180-(result*180)/Math.PI;dragndrop.angle=angle;}}}
else{$(this.canvas).css('cursor','move');var new_top_left_x=x-this.mouse_down_x;var new_top_left_y=y-this.mouse_down_y;var[x_corners,y_corners]=this.calculateCornerPositions(new_top_left_x,new_top_left_y,dragndrop.width,dragndrop.height,dragndrop.angle);var center_x=(x_corners[0]+x_corners[1]+x_corners[2]+x_corners[3])/4
var center_y=(y_corners[0]+y_corners[1]+y_corners[2]+y_corners[3])/4
var min_x_corner=x_corners[0];var max_x_corner=x_corners[3];var min_y_corner=y_corners[0];var max_y_corner=y_corners[3];if(min_x_corner<dragndrop.contain_x){var offset=center_x-min_x_corner-dragndrop.width/2;new_top_left_x=offset+dragndrop.contain_x;}
if(max_x_corner>dragndrop.contain_x+dragndrop.contain_width){var offset=max_x_corner-center_x-dragndrop.width/2;new_top_left_x=dragndrop.contain_x-offset+dragndrop.contain_width-dragndrop.width;}
if(min_y_corner<dragndrop.contain_y){var offset=center_y-min_y_corner-dragndrop.height/2;new_top_left_y=offset+dragndrop.contain_y;}
if(max_y_corner>dragndrop.contain_y+dragndrop.contain_height){var offset=max_y_corner-center_y-dragndrop.height/2;new_top_left_y=dragndrop.contain_y-offset+dragndrop.contain_height-dragndrop.height;}
dragndrop.x=new_top_left_x;dragndrop.y=new_top_left_y;dragndrop.center_x=dragndrop.x+dragndrop.width/2;dragndrop.center_y=dragndrop.y+dragndrop.height/2;dragndrop.changed=true;}
triggerRepaint();}
for(var i=this.dragndrops.length-1;i>=0;i--){var dragndrop=this.dragndrops[i];var[nx,ny]=rotate(dragndrop.center_x,dragndrop.center_y,x,y,dragndrop.angle);var startx=dragndrop.x;var starty=dragndrop.y;var endx=startx+dragndrop.width;var endy=starty+dragndrop.height;dragndrop.resizeable=false;dragndrop.moveable=false;if(nx>=startx&&nx<=endx&&ny>=starty&&ny<=endy&&dragndrop.mouse_down_action==''){$(this.canvas).css('cursor','move');dragndrop.moveable=true;}
if(dragndrop.editable&&dragndrop.selected){this.setCursorAtLocation(nx,ny,dragndrop.x-this.box_size_half,dragndrop.y-this.box_size_half,this.box_size,this.box_size,"nw-resize",dragndrop);this.setCursorAtLocation(nx,ny,dragndrop.x-this.box_size_half,dragndrop.y+dragndrop.height-this.box_size_half,this.box_size,this.box_size,"sw-resize",dragndrop);this.setCursorAtLocation(nx,ny,dragndrop.x+dragndrop.width-this.box_size_half,dragndrop.y-this.box_size_half,this.box_size,this.box_size,"ne-resize",dragndrop);this.setCursorAtLocation(nx,ny,dragndrop.x+dragndrop.width-this.box_size_half,dragndrop.y+dragndrop.height-this.box_size_half,this.box_size,this.box_size,"se-resize",dragndrop);this.setCursorAtLocation(nx,ny,dragndrop.x+dragndrop.width/2-this.box_size_half,dragndrop.y-this.box_size*2,this.box_size,this.box_size,"crosshair",dragndrop);if(dragndrop.width>2*this.box_size){this.setCursorAtLocation(nx,ny,dragndrop.x+dragndrop.width/2-this.box_size_half,dragndrop.y-this.box_size_half,this.box_size,this.box_size,"n-resize",dragndrop);this.setCursorAtLocation(nx,ny,dragndrop.x+dragndrop.width/2-this.box_size_half,dragndrop.y+dragndrop.height-this.box_size_half,this.box_size,this.box_size,"s-resize",dragndrop);}
if(dragndrop.height>2*this.box_size){this.setCursorAtLocation(nx,ny,dragndrop.x-this.box_size_half,dragndrop.y+dragndrop.height/2-this.box_size_half,this.box_size,this.box_size,"w-resize",dragndrop);this.setCursorAtLocation(nx,ny,dragndrop.x+dragndrop.width-this.box_size_half,dragndrop.y+dragndrop.height/2-this.box_size_half,this.box_size,this.box_size,"e-resize",dragndrop);}}
if(dragndrop.moveable||dragndrop.resizeable){return;}}
$(this.canvas).css('cursor','default');return;}
find(name){return;}
clear(){this.textbox.clear();this.circle.clear();this.dragndrops=[];this.mouse_down=false;this.mouse_down_x=null;this.mouse_down_y=null;}}class UITablePlan{constructor(canvas){this.canvas=canvas;this.uitableplans=[];this.dragndrop=new UIDragNDrop(this.canvas);this.button=new UIButton(this.canvas);this.numpad=new UINumpad(this.canvas);this.textbox=new UITextBox(this.canvas);this.min_width_height=24;}
add(options){options.editable=false;options.draw={mousedown_x:null,mousedown_y:null,mousemove_x:null,mousemove_y:null};options.redoable=[];options.undoable=[];options.elements=[];options.select=false;options.circle=false;options.rect=false;options.selected=null;options.isSelected=(object_selected)=>{if(options.selected!=object_selected){options.selected=object_selected;this.update();}
if(options.selected!=null){var obj=this.textbox.find(options.selected.group_id);obj.setText(options.selected.displaytext);}}
options.edit=(group_id)=>{this.dragndrop.setEditable(group_id,true);options.editable=true;options.select=true;this.update();}
options.colorInput=(color)=>{if(options.selected.background!=color){options.selected.background=color;options.selected.change();}}
options.numberInput=(val)=>{var obj=this.textbox.find(val.key);var obj_text=options.selected.displaytext;if(val.value>=0){obj_text=obj_text+val.value
obj.setText(obj_text);options.selected.displaytext=obj_text;options.selected.change();}
else if(val.value=='⌫'){obj_text=obj_text.slice(0,-1)
obj.setText(obj_text);options.selected.displaytext=obj_text;options.selected.change();}}
options.addToUndoable=(dragndrops)=>{options.redoable=[];options.undoable.push([...dragndrops]);}
options.save=(group_id)=>{this.dragndrop.setEditable(group_id,false);options.setSQLData();options.editable=false;options.circle=false;options.rect=false;this.update();}
options.setSQLData=()=>{executeSQL(`CREATE TABLE IF NOT EXISTS tableplan(id INTEGER PRIMARY KEY AUTOINCREMENT,\
name TEXT,\
data TEXT\);`);executeSQL(`DELETE FROM tableplan WHERE name='${options.name}';`);var data=options.undoable[options.undoable.length-1];data=JSON.stringify(data);executeSQL(`INSERT INTO tableplan(name,data)\
VALUES('${options.name}','${data}');`);}
options.getSQLData=()=>{var data=executeSQL(`SELECT data FROM tableplan WHERE name='${options.name}'`);var data=JSON.parse(data[0].values[0]);if(data.length>0){for(var i in data){data[i].callback=options.addToUndoable;data[i].isSelected=options.isSelected;this.dragndrop.add(data[i]);}}}
options.cancel=(group_id)=>{this.dragndrop.setEditable(group_id,false);options.editable=false;options.circle=false;options.selected=null;options.rect=false;options.undoable=[];options.redoable=[];this.dragndrop.dragndrops=[];options.getSQLData();this.update();}
options.selectTable=(group_id)=>{$(this.canvas).css('cursor','default');this.dragndrop.setEditable(group_id,true);options.circle=false;options.rect=false;options.select=true;this.update();}
options.drawCircle=(group_id)=>{$(this.canvas).css('cursor','crosshair');this.dragndrop.setEditable(group_id,false);options.circle=true;options.selected=null;options.select=false;options.rect=false;this.update();}
options.drawRect=(group_id)=>{this.dragndrop.setEditable(group_id,false);$(this.canvas).css('cursor','crosshair');options.rect=true;options.selected=null;options.select=false;options.circle=false;this.update();}
options.undo=(group_id)=>{if(options.undoable.length>0){this.dragndrop.replaceElementsByGropID(group_id,options.undoable[options.undoable.length-2]);options.redoable.push(options.undoable[options.undoable.length-1]);options.undoable.pop();}}
options.redo=(group_id)=>{if(options.redoable.length>0){this.dragndrop.replaceElementsByGropID(group_id,options.redoable[options.redoable.length-1]);options.undoable.push(options.redoable[options.redoable.length-1]);options.redoable.pop();if(options.circle||options.rect){this.dragndrop.setEditable(group_id,false);}
else if(options.select){this.dragndrop.setEditable(group_id,true);}}}
options.deleteSelected=(group_id)=>{options.selected=null;this.dragndrop.deleteSelected(group_id);this.update();}
this.uitableplans.push(options);this.update();return options;}
update(){this.button.clear();this.numpad.clear();this.textbox.clear();for(var i in this.uitableplans){var uitableplan=this.uitableplans[i];if(uitableplan.editable==false){this.button.add({displaytext:'🖉 Bearbeiten',background:['#4fbcff','#009dff'],foreground:'#000000',border:'#4fbcff',border_width:3,grd_type:'vertical',x:uitableplan.x+20,y:uitableplan.y+uitableplan.height-60,width:150,height:45,border_radius:20,font_size:18,hover_border:'#009dff',callback:uitableplan.edit,callbackData:i});this.numpad.add({show_keys:{x:false,ZWS:false},background:['#f9a004','#ff0202'],foreground:'#000000',border:'#FF0000',grd_type:'vertical',border_width:1,hover_border:'#ffffff',x:uitableplan.x+uitableplan.width-210,y:uitableplan.y+uitableplan.height-350-70,width:200,height:340,border_radius:10,font_size:20,gap:10,callback:buttonSendMessage,callbackData:{key:"Numpad"}});}
else{this.button.add({displaytext:'⮪',background:['#4fbcff','#009dff'],foreground:'#000000',border:'#4fbcff',border_width:3,grd_type:'vertical',x:uitableplan.x+10,y:uitableplan.y+uitableplan.height-60,width:50,height:50,border_radius:10,font_size:30,hover_border:'#009dff',callback:uitableplan.undo,callbackData:i});this.button.add({displaytext:'⮫',background:['#4fbcff','#009dff'],foreground:'#000000',border:'#4fbcff',border_width:3,grd_type:'vertical',x:uitableplan.x+70,y:uitableplan.y+uitableplan.height-60,width:50,height:50,border_radius:10,font_size:30,hover_border:'#009dff',callback:uitableplan.redo,callbackData:i});this.button.add({displaytext:'➕⬜',background:['#4fbcff','#009dff'],foreground:'#000000',border:'#4fbcff',border_width:3,grd_type:'vertical',x:uitableplan.x+130,y:uitableplan.y+uitableplan.height-60,width:50,height:50,border_radius:10,font_size:30,hover_border:'#009dff',callback:uitableplan.drawRect,callbackData:i});this.button.add({displaytext:'➕◯',background:['#4fbcff','#009dff'],foreground:'#000000',border:'#4fbcff',border_width:3,grd_type:'vertical',x:uitableplan.x+190,y:uitableplan.y+uitableplan.height-60,width:50,height:50,border_radius:10,font_size:30,hover_border:'#009dff',callback:uitableplan.drawCircle,callbackData:i});this.button.add({displaytext:"🖰",background:['#4fbcff','#009dff'],foreground:'#000000',border:'#4fbcff',border_width:3,grd_type:'vertical',x:uitableplan.x+250,y:uitableplan.y+uitableplan.height-60,width:50,height:50,border_radius:10,font_size:30,hover_border:'#009dff',callback:uitableplan.selectTable,callbackData:i});this.button.add({displaytext:"🗑️",background:['#ff0000','#cc000a'],foreground:'#000000',border:'#ff0000',border_width:3,grd_type:'vertical',x:uitableplan.x+310,y:uitableplan.y+uitableplan.height-60,width:50,height:50,border_radius:10,font_size:30,hover_border:'#cc000a',callback:uitableplan.deleteSelected,callbackData:i});this.button.add({displaytext:'🗙 Abbrechen',background:['#ff948c','#ff1100',],foreground:'#000000',border:'#ff948c',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-170,y:uitableplan.y+uitableplan.height-60,width:150,height:45,border_radius:20,font_size:18,hover_border:'#ff1100',callback:uitableplan.cancel,callbackData:i});this.button.add({displaytext:'💾 Speichern',background:['#39f500','#32d600'],foreground:'#000000',border:'#39f500',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-350,y:uitableplan.y+uitableplan.height-60,width:150,height:45,border_radius:20,font_size:18,hover_border:'#32d600',callback:uitableplan.save,callbackData:i});if(uitableplan.selected!=null){this.numpad.add({show_keys:{x:false,ZWS:false},background:['#f9a004','#ff0202'],foreground:'#000000',border:'#FF0000',grd_type:'vertical',border_width:1,hover_border:'#ffffff',x:uitableplan.x+uitableplan.width-210,y:uitableplan.y+uitableplan.height-350-70,width:200,height:340,border_radius:10,font_size:20,gap:10,callback:uitableplan.numberInput,callbackData:{key:i}});this.textbox.add({displaytext:'',name:i,background:['#ffffff'],foreground:'#000000',border:'#000000',border_width:3,x:uitableplan.x+uitableplan.width-210,y:uitableplan.y+uitableplan.height-350-140,width:190,height:50,font_size:30,align:'right'});this.button.add({displaytext:"",background:['#493C2B'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-210,y:uitableplan.y+10,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#493C2B']});this.button.add({displaytext:"",background:['#A46422'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-160,y:uitableplan.y+10,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#A46422']});this.button.add({displaytext:"",background:['#EB8931'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-110,y:uitableplan.y+10,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#EB8931']});this.button.add({displaytext:"",background:['#2F484E'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-60,y:uitableplan.y+10,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#2F484E']});this.button.add({displaytext:"",background:['#44891A'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-210,y:uitableplan.y+60,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#44891A']});this.button.add({displaytext:"",background:['#1B2632'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-160,y:uitableplan.y+60,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#1B2632']});this.button.add({displaytext:"",background:['#005784'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-110,y:uitableplan.y+60,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#005784']});this.button.add({displaytext:"",background:['#31A2F2'],foreground:'#000000',border:'#ffffff',border_width:3,grd_type:'vertical',x:uitableplan.x+uitableplan.width-60,y:uitableplan.y+60,width:40,height:40,border_radius:5,font_size:30,hover_border:'#ffffff',callback:uitableplan.colorInput,callbackData:['#31A2F2']});}}}
triggerRepaint();}
render(ctx){for(var i in this.uitableplans){var uitableplan=this.uitableplans[i];ctx.fillStyle=uitableplan.background[0];ctx.lineWidth=uitableplan.border_width;ctx.fillRect(uitableplan.x,uitableplan.y,uitableplan.width,uitableplan.height);ctx.fillStyle='#A9A9A9';ctx.fillRect(uitableplan.x+uitableplan.border_width/2,uitableplan.y+uitableplan.height-70,uitableplan.width-uitableplan.border_width,70-uitableplan.border_width/2);ctx.fillRect(uitableplan.x+uitableplan.width-225,uitableplan.y+uitableplan.border_width/2,225-uitableplan.border_width/2,uitableplan.height-uitableplan.border_width);ctx.strokeStyle=uitableplan.border;ctx.strokeRect(uitableplan.x,uitableplan.y,uitableplan.width,uitableplan.height);if(uitableplan.draw.mousedown_x!=null){if(uitableplan.rect){ctx.fillStyle='#31A2F2';ctx.fillRect(uitableplan.draw.mousedown_x+uitableplan.x,uitableplan.draw.mousedown_y+uitableplan.y,uitableplan.draw.mousemove_x-uitableplan.draw.mousedown_x,uitableplan.draw.mousemove_y-uitableplan.draw.mousedown_y);}
else if(uitableplan.circle){ctx.beginPath();ctx.fillStyle='#31A2F2';var ellipse_radius_x=(uitableplan.draw.mousedown_x-uitableplan.draw.mousemove_x)/2;var ellipse_radius_y=(uitableplan.draw.mousedown_y-uitableplan.draw.mousemove_y)/2;var ellipse_center_x=uitableplan.draw.mousedown_x+uitableplan.x-ellipse_radius_x;var ellipse_center_y=uitableplan.draw.mousedown_y+uitableplan.y-ellipse_radius_y;if(ellipse_radius_x<0){ellipse_radius_x=(uitableplan.draw.mousemove_x-uitableplan.draw.mousedown_x)/2
ellipse_center_x=uitableplan.draw.mousedown_x+uitableplan.x+ellipse_radius_x;}
if(ellipse_radius_y<0){ellipse_radius_y=(uitableplan.draw.mousemove_y-uitableplan.draw.mousedown_y)/2
ellipse_center_y=uitableplan.draw.mousedown_y+uitableplan.y+ellipse_radius_y;}
ctx.ellipse(ellipse_center_x,ellipse_center_y,ellipse_radius_x,ellipse_radius_y,0,0,2*Math.PI);ctx.fill();}}}
this.button.render(ctx);this.numpad.render(ctx);this.dragndrop.render(ctx);this.textbox.render(ctx);}
onClick(x,y){this.button.onClick(x,y);this.numpad.onClick(x,y);this.dragndrop.onClick(x,y);}
onMouseDown(x,y){for(var i in this.uitableplans){var uitableplan=this.uitableplans[i];if(!uitableplan.circle&&!uitableplan.rect&&uitableplan.editable){this.dragndrop.onMouseDown(x,y);}
if(uitableplan.editable==true&&(uitableplan.circle==true||uitableplan.rect==true)){if(x>uitableplan.x&&x<uitableplan.x+uitableplan.width-225&&y>uitableplan.y&&y<uitableplan.y+uitableplan.height-70){uitableplan.draw.mousedown_x=x-uitableplan.x;uitableplan.draw.mousedown_y=y-uitableplan.y;uitableplan.draw.mousemove_x=x-uitableplan.x;uitableplan.draw.mousemove_y=y-uitableplan.y;}}
else{uitableplan.draw.mousedown_x=null;uitableplan.draw.mousedown_y=null;}}
this.button.onMouseDown(x,y);this.numpad.onMouseDown(x,y);}
convertRelativePosition(){}
onMouseUp(x,y){for(var i in this.uitableplans){var uitableplan=this.uitableplans[i];if(uitableplan.editable==true&&(uitableplan.circle==true||uitableplan.rect==true)&&uitableplan.draw.mousedown_x!=null){var x=0;var y=0;var width=0;var height=0;if(uitableplan.draw.mousemove_x-uitableplan.draw.mousedown_x>0){x=uitableplan.draw.mousedown_x+uitableplan.x;width=uitableplan.draw.mousemove_x-uitableplan.draw.mousedown_x;}
else{x=uitableplan.draw.mousemove_x+uitableplan.x;width=uitableplan.draw.mousedown_x-uitableplan.draw.mousemove_x;}
if(uitableplan.draw.mousemove_y-uitableplan.draw.mousedown_y>0){y=uitableplan.draw.mousedown_y+uitableplan.y;height=uitableplan.draw.mousemove_y-uitableplan.draw.mousedown_y;}
else{y=uitableplan.draw.mousemove_y+uitableplan.y;height=uitableplan.draw.mousedown_y-uitableplan.draw.mousemove_y;}
if(width<this.min_width_height){width=this.min_width_height;}
if(height<this.min_width_height){height=this.min_width_height;}
if(x+width>uitableplan.x+uitableplan.width-225){x=uitableplan.x+uitableplan.width-225-width;}
if(y+height>uitableplan.y+uitableplan.height-70){y=uitableplan.y+uitableplan.height-70-height;}
if(uitableplan.rect){this.dragndrop.add({displaytext:'',group_id:i,contain_x:uitableplan.x,contain_y:uitableplan.y,contain_width:uitableplan.width-225,contain_height:uitableplan.height-70,background:['#31A2F2'],foreground:'#000000',border:'#0579ff',border_width:0,grd_type:'vertical',editable:true,x:x,y:y,width:width,height:height,font_size:25,angle:0,callback:uitableplan.addToUndoable,isSelected:uitableplan.isSelected});}
else if(uitableplan.circle){this.dragndrop.add({displaytext:'',group_id:i,contain_x:uitableplan.x,contain_y:uitableplan.y,contain_width:uitableplan.width-225,contain_height:uitableplan.height-70,background:['#31A2F2'],foreground:'#000000',border:'#0579ff',border_width:0,grd_type:'vertical',editable:true,type:'circle',x:x,y:y,width:width,height:height,font_size:25,angle:0,callback:uitableplan.addToUndoable,isSelected:uitableplan.isSelected});}
uitableplan.draw.mousedown_x=null;uitableplan.draw.mousedown_y=null;uitableplan.draw.mousemove_x=null;uitableplan.draw.mousemove_y=null;this.update();}}
this.button.onMouseUp(x,y);this.numpad.onMouseUp(x,y);this.dragndrop.onMouseUp(x,y);}
onMouseMove(x,y){for(var i in this.uitableplans){var uitableplan=this.uitableplans[i];if(uitableplan.select){this.dragndrop.onMouseMove(x,y);}
else if(uitableplan.rect||uitableplan.circle){$(this.canvas).css('cursor','crosshair');}
if(uitableplan.editable==true&&(uitableplan.circle==true||uitableplan.rect==true)){uitableplan.draw.mousemove_x=x-uitableplan.x;uitableplan.draw.mousemove_y=y-uitableplan.y;if(x<uitableplan.x){uitableplan.draw.mousemove_x=0;}
else if(x>uitableplan.x+uitableplan.width-225){uitableplan.draw.mousemove_x=uitableplan.width-225;}
if(y<uitableplan.y){uitableplan.draw.mousemove_y=0;}
else if(y>uitableplan.y+uitableplan.height-70){uitableplan.draw.mousemove_y=uitableplan.height-70;}
triggerRepaint();}
else{uitableplan.draw.mousemove_x=null;uitableplan.draw.mousemove_y=null;}}
this.button.onMouseMove(x,y);this.numpad.onMouseMove(x,y);}
find(name){for(var i in this.uitableplans){var uitableplan=this.uitableplans[i];if(uitableplan.name==name){return uitableplan;}}}}class UICircle{constructor(canvas){this.canvas=canvas;this.circles=[];}
add(options){this.circles.push(options);return options;}
render(ctx){for(var i in this.circles){var circle=this.circles[i];ctx.font=circle.font_size+'px Courier';ctx.strokeStyle=circle.border;ctx.lineWidth=circle.border_width;var grd;if(circle.grd_type=='horizontal'){grd=ctx.createLinearGradient(circle.x,circle.y,circle.x+circle.width,circle.y);}
else if(circle.grd_type=='vertical'){grd=ctx.createLinearGradient(circle.x,circle.y,circle.x,circle.y+circle.height);}
if(circle.grd_type){var step_size=1/circle.background.length;for(var j in circle.background){grd.addColorStop(step_size*j,circle.background[j]);ctx.fillStyle=grd;}}
if(circle.background.length==1){ctx.fillStyle=circle.background[0];}
var radius_y=circle.height/2;var radius_x=circle.width/2;var ellipse_center_x=circle.x+radius_x;var ellipse_center_y=circle.y+radius_y;ctx.save();ctx.clearRect(0,0,this.canvas.width,this.canvas.height);ctx.translate(circle.center_x,circle.center_y);ctx.rotate(circle.angle*Math.PI/180);ctx.translate(-circle.center_x,-circle.center_y)
ctx.beginPath();ctx.ellipse(ellipse_center_x,ellipse_center_y,radius_x,radius_y,0,0,2*Math.PI);ctx.fill();if(circle.border_width!=0&&circle.border_width!=undefined){ctx.stroke();}
console.log(circle.foreground);ctx.restore();ctx.fillStyle=circle.foreground;ctx.strokeStyle=circle.foreground;if(circle.displaytext){if(!circle.displaytext.includes("\n")){var text_width=ctx.measureText(circle.displaytext).width;if(circle.align=='right'){ctx.fillText(circle.displaytext,circle.x+circle.width-text_width-8,circle.y+(circle.height/2)+circle.font_size/3.3);}
else if(circle.align=='left'){ctx.fillText(circle.displaytext,circle.x+8,circle.y+(circle.height/2)+circle.font_size/3.3);}
else{ctx.fillText(circle.displaytext,circle.x+(circle.width-text_width)/2,circle.y+(circle.height/2)+circle.font_size/3.3);}}else{var blines=circle.displaytext.split("\n");var yoffs=circle.y+((circle.height/2)-(9*(blines.length-1)));for(var j=0;j<blines.length;j++){if(circle.align=='right'){blines[j].replace("\n",'');var text_width=ctx.measureText(blines[j]).width;ctx.fillText(blines[j],circle.x+circle.width-text_width-8,yoffs);}
else{blines[j].replace("\n",'');ctx.fillText(blines[j],circle.x+8,yoffs);}
yoffs=yoffs+18;}}}}}
onClick(x,y){return;}
onMouseDown(x,y){return;}
onMouseUp(x,y){return;}
onMouseMove(x,y){return;}
find(name){return;}
clear(){this.circles=[];}}