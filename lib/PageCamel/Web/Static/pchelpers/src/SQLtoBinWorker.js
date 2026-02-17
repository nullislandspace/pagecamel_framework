"use strict";
// We get potentially hundreds of save/convert requests per second. We only need to save the *latest* one.
// So we run the main conversion at relatively long intervals (500ms). If multiple conversion requests come
// in the meantime, we only work on the last one.
// Using pako (gzip) instead of LZString - much faster compression (ms vs seconds)
importScripts("/static/pako.min.js");
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
    var uarr = new Uint8Array(nextSave);
    var saveID = nextSaveID;
    hasnextSave = false;

    // Compress with pako (gzip) - much faster than LZString
    var compressed = pako.deflate(uarr);

    // Convert compressed Uint8Array to string for IndexedDB storage
    // Prefix with "GZIP:" marker so loader knows the format
    var strings = ["GZIP:"], chunksize = 0x00ff;
    for (var i = 0; i * chunksize < compressed.length; i++) {
        var numarr = Array.from(compressed.subarray(i * chunksize, (i + 1) * chunksize));
        strings.push(String.fromCharCode.apply(null, numarr));
    }
    var result = strings.join("");

    postMessage(["SAVEDB", result, saveID]);
    return;
}
