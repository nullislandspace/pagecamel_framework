"use strict";
importScripts("/static/lz-string.js");
var nextSave;
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
            console.log("Dropping intermediate conversion request");
        }
        nextSave = e.data[1];
        hasnextSave = true;
    }
};
function dataConverter() {
    if (!hasnextSave) {
        return;
    }
    hasnextSave = false;
    var uarr = new Uint8Array(nextSave);
    var strings = [], chunksize = 0x00ff;
    for (var i = 0; i * chunksize < uarr.length; i++) {
        var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
        strings.push(String.fromCharCode.apply(null, numarr));
    }
    var result = strings.join("");
    console.log("DB SAVE IS " + result.length + " bytes long");
    var compressed = LZString.compress(result);
    console.log("Compressed DB SAVE IS " + compressed.length + " bytes long");
    console.log("Compressed to " + ((compressed.length / result.length) * 100) + "% of original size");
    postMessage(["SAVEDB", compressed]);
    return;
}
//# sourceMappingURL=SQLtoBinWorker.js.map