// We get potentially hundreds of save/convert requests per second. We only need to save the *latest* one.
// So we run the main conversion at relatively long intervals (500ms). If multiple conversion requests come
// in the meantime, we only work on the last one.

importScripts("/static/lz-string.js");

var nextSave : Uint8Array;
var hasnextSave = false;
var intervalhandler : any;

declare var LZString: {
    compress: (
        data: string
    ) => string;
    decompress: (
        data: string
    ) => string;
};

onmessage = function (e: MessageEvent): void {
    var command = e.data[0] as string;
    //var data = e.data[1] as Uint8Array;

    if (command == "START") {
        intervalhandler = setInterval(dataConverter, 500);
    } else if (command == "STOP") {
        clearInterval(intervalhandler);
    } else if (command == "SQLTOSTRING") {
        if(hasnextSave) {
            console.log("Dropping intermediate conversion request");
        }
        nextSave = e.data[1];
        hasnextSave = true;
    }
};

function dataConverter() {
    if(!hasnextSave) {
        return;
    }

    hasnextSave = false;

    var uarr: Uint8Array = new Uint8Array(nextSave);
    var strings: string[] = [],
        chunksize: number = 0x00ff;
    // There is a maximum stack size. We cannot call String.fromCharCode with as many arguments as we want

    for (var i = 0; i * chunksize < uarr.length; i++) {
        var numarr: number[] = Array.from(
            uarr.subarray(i * chunksize, (i + 1) * chunksize)
        );
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
