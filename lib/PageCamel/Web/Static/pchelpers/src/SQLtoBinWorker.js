
onmessage = function(e) {
    var command = e.data[0];
    var data = e.data[1];

    if(command == 'SQLTOSTRING') {
        var uarr = new Uint8Array(data);
        var strings = [], chunksize = 0x00ff;
        // There is a maximum stack size. We cannot call String.fromCharCode with as many arguments as we want

        for (var i = 0; i * chunksize < uarr.length; i++) {
            var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
            strings.push(String.fromCharCode.apply(null, numarr));
        }
        //console.log("DB SAVE IS " + strings.length + " bytes long");
        postMessage(['SAVEDB', strings.join('')]);
    }
}

