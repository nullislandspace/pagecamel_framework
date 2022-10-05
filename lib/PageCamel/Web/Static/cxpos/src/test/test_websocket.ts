import { CXWebsocket, CallbackType } from "../cxadds/websocket.js"; 

let ws = new CXWebsocket();

function onTestMessage(cbname:string, data:string):void{
    console.log("Callback onTestMessage called");
} 
ws.register("testmessage",[onTestMessage] );

