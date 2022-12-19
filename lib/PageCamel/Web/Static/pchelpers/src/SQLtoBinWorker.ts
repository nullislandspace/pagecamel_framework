onmessage = function (e: MessageEvent): void {
    var command = e.data[0] as string;
    var data = e.data[1] as Uint8Array;

    if (command == "SQLTOSTRING") {
        var uarr: Uint8Array = new Uint8Array(data);
        var strings: string[] = [],
            chunksize: number = 0x00ff;
        // There is a maximum stack size. We cannot call String.fromCharCode with as many arguments as we want

        for (var i = 0; i * chunksize < uarr.length; i++) {
            var numarr: number[] = Array.from(
                uarr.subarray(i * chunksize, (i + 1) * chunksize)
            );
            strings.push(String.fromCharCode.apply(null, numarr));
        }
        //console.log("DB SAVE IS " + strings.length + " bytes long");
        postMessage(["SAVEDB", strings.join("")]);
    }
};
