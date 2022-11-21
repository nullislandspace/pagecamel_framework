import { PCWebsocket } from '../websocket.js';
import { PCSqlite } from '../sqlite.js';
declare var window: any;



                // Normally Sql.js tries to load sql-wasm.wasm relative to the page, not relative to the javascript
                // doing the loading. So, we help it find the .wasm file with this function.
                var fname = './src/sql-wasm.wasm';
                var config = {
                    locateFile: (filename:string) => fname
                };





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

    window.pcws.isconnected = false;

    /*window.sqlite.executeSQL("create table test (msg text, data text);");
    window.sqlite.executeSQL("insert into test (msg ,data) values ('tt1', 'undsowwwweit');");
    window.sqlite.executeSQL("select * from test");*/
    window.pcws.send("cachemessage","Meine Daten1 sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten2 sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten3 sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten4 sind ziemlich kurz!", true);
    window.sqlite.executeSQL("select * from wstransmit");

    /*window.pcws.send("Testmessage","Meine Daten sind ziemlich kurz!");
    window.pcws.send("cachemessage","Meine Daten sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine Daten sind ziemlich kurz!", true);*/
    window.pcws.isconnected = true;
    window.pcws.deregister("testmessage", [] );
    window.pcws.deregister("testmessage", [onTestMessage] );
    window.pcws.deregister("testmessage", [onTestMessage2] );
    window.pcws.deregister("testmessage2", [onTestMessage2] );

    window.pcws.reset();



}

document.body.onload = bodyOnLoad;

function bodyOnLoad() {
    main();
}
function main() {
    window.sqlite = new PCSqlite(config,"pagecamel.sqlite",false);
    window.pcws = new PCWebsocket(true,true);
    window.sqlite.initialize.then(()=>{
        window.pcws.initializeSQL(window.sqlite)
        onLoadExt();
    }).catch((msg:string)=>{console.error("Error at SQL initialisation: " + msg)});   
}
