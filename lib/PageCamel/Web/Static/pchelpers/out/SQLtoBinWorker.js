"use strict";
importScripts("/static/lz-string.js");
var nextSave;
var nextSaveID = 0;
var hasnextSave = false;
var intervalhandler;
onmessage = function (e) {
    var command = e.data[0];
    if (command == "START") {
        intervalhandler = setInterval(dataConverter, 500);
    }
    else if (command == "STOP") {
        clearInterval(intervalhandler);
    }
    else if (command == "SQLTOSTRING") {
        if (hasnextSave) {
        }
        nextSave = e.data[1];
        nextSaveID = e.data[2];
        hasnextSave = true;
    }
};
function dataConverter() {
    if (!hasnextSave) {
        return;
    }
    var uarr = new Uint8Array(nextSave);
    var saveID = nextSaveID;
    hasnextSave = false;
    var strings = [], chunksize = 0x00ff;
    for (var i = 0; i * chunksize < uarr.length; i++) {
        var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
        strings.push(String.fromCharCode.apply(null, numarr));
    }
    var result = strings.join("");
    var compressed = LZString.compress(result);
    postMessage(["SAVEDB", compressed, saveID]);
    return;
}
//# sourceMappingURL=SQLtoBinWorker.js.map