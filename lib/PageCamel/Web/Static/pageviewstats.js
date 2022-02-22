var _pagecamel_visible_starttime = 0;
var _pagecamel_visible_count = 0;

function _init_pagecamel_pageviewstats() {
    if(!navigator.sendBeacon) {
        console.log("Browser does NOT support beacon API!");
        return 0;
    }
    //console.log("%cCollecting anonymous page view stats.", "background: red; color: yellow; font-size: x-large");
    //console.log("%cThis data is only used to find the most used pages, so they get the highest priority for optimization.", "background: red; color: yellow");

    if(document.visibilityState !== 'hidden') {
        _pagecamel_visible_starttime = new Date().getTime() / 1000;
        _pagecamel_visible_count++;
    }

    document.addEventListener('visibilitychange', function() {
        if(document.visibilityState === 'hidden') {
            _send_pagecamel_pageviewstats('hidden');
        } else {
            _pagecamel_visible_starttime = new Date().getTime() / 1000;
            _pagecamel_visible_count++;
        }
    });

    window.addEventListener('unload', function() {
        _send_pagecamel_pageviewstats('unload');
    });
    window.addEventListener('beforeunload', function() {
        _send_pagecamel_pageviewstats('beforeunload');
    });
    
    function _send_pagecamel_pageviewstats(changetype) {
        if(_pagecamel_visible_starttime === 0) {
            // Already invisible or unloading
            return;
        }
        var _pagecamel_visible_endtime = new Date().getTime() / 1000;
        var _pagecamel_visible_duration = _pagecamel_visible_endtime - _pagecamel_visible_starttime;
        _pagecamel_visible_duration = Math.round((_pagecamel_visible_duration) * 100) / 100; // Round to 2 decimals

        var _pagecamel_visibility_report = JSON.stringify({
            uri: window.location.href,
            duration: _pagecamel_visible_duration,
            count: _pagecamel_visible_count,
            type: changetype
        });
        _pagecamel_visible_starttime = 0;
        navigator.sendBeacon('/public/pageviewstats', _pagecamel_visibility_report);
    }

    return 1;
}
