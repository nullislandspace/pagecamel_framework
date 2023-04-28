function onTestMessage(msgname, data) {
    console.log("Please note onTestMessage data: " + data);
}
function onTestMessage2(msgname, data) {
    console.log("Callback onTestMessage2: " + data);
}
function getConnectionStatus(msgname, data) {
    console.log("Connection status: " + data);
}
export function onLoadExt() {
    window.pcws.send("SLEEP", "Sleep message wartet 7 Sekunden", true);
    let data = {
        'table': '10',
        'type': 'delta',
        'delta': {},
        'split': false,
    };
}
//# sourceMappingURL=test_websocket.js.map