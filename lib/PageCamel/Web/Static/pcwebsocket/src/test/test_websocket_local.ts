import { PCWebsocket } from '../websocket.js';
import { PCSqlite } from '../sqlite.js';
declare var window: any;



                // Normally Sql.js tries to load sql-wasm.wasm relative to the page, not relative to the javascript
                // doing the loading. So, we help it find the .wasm file with this function.
                var fname = './src/sql-wasm.wasm';
                var config = {
                    locateFile: (filename:string) => fname
                };


window.sqlite = new PCSqlite(config,"",true);
window.pcws = new PCWebsocket(true,true);
window.pcws.initializeSQL(window.sqlite);

function wstransmit(msgname:string, data:string, id:string) {};
window.wstransmit = wstransmit;

function onTestMessage(msgname:string, data:string):void{
    console.log("Please note onTestMessage data: " + data);
} 

function onTestMessage2(msgname:string, data:string):void{
    console.log("Callback onTestMessage2: "+ data);
} 

function getConnectionStatus(msgname:string, data:string):void {
    console.log("Connection status: " + data);
}


function onLoadExt () {
    window.pcws.register("NOTIFICATION",[onTestMessage] );
    window.pcws.register("RECIEVED",[onTestMessage2] );
    window.pcws.register("testmessage",[onTestMessage, onTestMessage2] );
    
    window.pcws.register("isconnected", [getConnectionStatus]);

    window.pcws.isconnected = true;

    /*window.pcws.send("Testmessage","Meine Daten sind ziemlich kurz!");
    window.pcws.send("cachemessage","Meine Daten sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten sind ziemlich kurz!", true);
    */
    window.pcws.deregister("testmessage", [] );
    window.pcws.deregister("testmessage", [onTestMessage] );
    window.pcws.deregister("testmessage", [onTestMessage2] );
    window.pcws.deregister("testmessage2", [onTestMessage2] );



}


document.body.onload = bodyOnLoad;
function bodyOnLoad() {
    main();
}
function main() {
    onLoadExt();
}
