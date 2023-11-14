"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const websocket_js_1 = require("../websocket.js");
const sqlite_js_1 = require("../sqlite.js");
var fname = './src/sql-wasm.wasm';
var config = {
    locateFile: (filename) => fname
};
function wstransmit(msgname, data, id) { }
;
window.wstransmit = wstransmit;
function onTestMessage(msgname, data) {
    console.log("Please note onTestMessage data: " + data);
}
function onTestMessage2(msgname, data) {
    console.log("Callback onTestMessage2: " + data);
}
function getConnectionStatus(msgname, data) {
    console.log("Connection status: " + data);
}
function onLoadExt() {
    window.pcws.register("NOTIFICATION", [onTestMessage]);
    window.pcws.register("RECIEVED", [onTestMessage2]);
    window.pcws.register("testmessage", [onTestMessage, onTestMessage2]);
    window.pcws.register("isconnected", [getConnectionStatus]);
    window.pcws.isconnected = false;
    window.pcws.send("cachemessage", "Meine Daten1 sind ziemlich kurz!", true);
    window.pcws.send("cachemessage", "Meine Daten2 sind ziemlich kurz!", true);
    window.pcws.send("cachemessage", "Meine Daten3 sind ziemlich kurz!", true);
    window.pcws.send("cachemessage", "Meine Daten4 sind ziemlich kurz!", true);
    window.sqlite.executeSQL("select * from wstransmit");
    window.pcws.isconnected = true;
    window.pcws.deregister("testmessage", []);
    window.pcws.deregister("testmessage", [onTestMessage]);
    window.pcws.deregister("testmessage", [onTestMessage2]);
    window.pcws.deregister("testmessage2", [onTestMessage2]);
    window.pcws.reset();
}
document.body.onload = bodyOnLoad;
function bodyOnLoad() {
    main();
}
function main() {
    window.sqlite = new sqlite_js_1.PCSqlite({
        config: config,
        dbname: "pagecamel.sqlite",
        debug: false,
    });
    window.pcws = new websocket_js_1.PCWebsocket(true, true);
    window.sqlite.initialize.then(() => {
        window.pcws.initializeSQL(window.sqlite);
        onLoadExt();
    }).catch((msg) => { console.error("Error at SQL initialisation: " + msg); });
}
//# sourceMappingURL=test_websocket_local.js.map