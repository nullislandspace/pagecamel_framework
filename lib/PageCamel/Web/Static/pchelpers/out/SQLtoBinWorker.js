"use strict";
// We get potentially hundreds of save/convert requests per second. We only need to save the *latest* one.
// So we run the main conversion at relatively long intervals (500ms). If multiple conversion requests come
// in the meantime, we only work on the last one.
importScripts("/static/lz-string.js");
var nextSave;
var nextSaveID = 0;
var hasnextSave = false;
var intervalhandler;
onmessage = function (e) {
    var command = e.data[0];
    //var data = e.data[1] as Uint8Array;
    if (command == "START") {
        intervalhandler = setInterval(dataConverter, 20);
    }
    else if (command == "STOP") {
        clearInterval(intervalhandler);
    }
    else if (command == "SQLTOSTRING") {
        if (hasnextSave) {
            //console.log("Dropping intermediate conversion request");
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
    //console.log("Saving");
    //var starttime = Date.now();
    var uarr = new Uint8Array(nextSave);
    var saveID = nextSaveID;
    hasnextSave = false;
    var strings = [], chunksize = 0x00ff;
    // There is a maximum stack size. We cannot call String.fromCharCode with as many arguments as we want
    for (var i = 0; i * chunksize < uarr.length; i++) {
        var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
        strings.push(String.fromCharCode.apply(null, numarr));
    }
    var result = strings.join("");
    //var midtime = Date.now();
    //console.log("DB SAVE IS " + result.length + " bytes long");
    var compressed = LZString.compress(result);
    /*
    var endtime = Date.now();
    console.log("conversion took " + ((midtime - starttime) / 1000) + " seconds");
    console.log("compression took " + ((endtime - midtime) / 1000) + " seconds");
    console.log("Uncompressed DB SAVE IS " + result.length + " bytes long");
    console.log("Compressed DB SAVE IS " + compressed.length + " bytes long");
    console.log("Compressed to " + ((compressed.length / result.length) * 100) + "% of original size");
    */
    postMessage(["SAVEDB", compressed, saveID]);
    return;
}
