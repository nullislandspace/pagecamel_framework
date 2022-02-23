// Override console logging
console.log("Remote developer console active");
if (console.everything === undefined) {
    console.everything = [];
    console.logdirect = 0;

    console.silentlog = function(logdata) {
        console.everything.push({
            type: 'silent',
            timeStamp: TS(),
            value: logdata
        });
    }

    function TS(){
        return (new Date).toLocaleString("sv", { timeZone: 'UTC' }) + "Z"
    }

    window.onerror = function (error, url, line) {
        console.everything.push({
            type: "exception",
            timeStamp: TS(),
            value: { error, url, line }
        });
        return false;
    }
    window.onunhandledrejection = function (e) {
        console.everything.push({
            type: "promiseRejection",
            timeStamp: TS(),
            value: e.reason
        });
    }

    function hookLogType(logType) {
        const original= console[logType].bind(console)
        return function() {
            if(console.logdirect == 0) {
                console.everything.push({
                    type: logType,
                    timeStamp: TS(),
                    value: Array.from(arguments)
                });
            }
            original.apply(console, arguments)
        }
    }

    ['log', 'error', 'warn', 'debug'].forEach(logType=>{
        console[logType] = hookLogType(logType);
    });

    document.addEventListener("keyup", function(e) {
        if(e.key == "F9") {
            console.logdirect = 1;
            console.log("Sending beacon");
            var jsonlog = JSON.stringify(console.everything);
            navigator.sendBeacon('/public/remoteconsolelog/beacon', jsonlog);
            console.logdirect = 0;
        }
    });
}


