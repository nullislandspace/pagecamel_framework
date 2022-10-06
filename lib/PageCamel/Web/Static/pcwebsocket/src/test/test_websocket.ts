import { CXWebsocket, CallbackType } from "../websocket.js"; 

let ws = new CXWebsocket(false, true);

function onTestMessage(cbname:string, data:string):void{
    console.log("Callback onTestMessage called");
} 

function onTestMessage2(cbname:string, data:string):void{
    //console.log("Callback " + this.name + " called");
} 
ws.register("testmessage",[onTestMessage] );
ws.register("testmessage",[onTestMessage2] );

