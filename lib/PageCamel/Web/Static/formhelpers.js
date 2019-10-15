// This script file holds various helper functions
// commonly used in PageCamel forms


function setMode(elemID, modeVal) {
    var modeElem = document.getElementById(elemID);
    modeElem.value = modeVal;
    return true;
}

function serializeList(listID, inputID) {
	var listElems = $(listID).sortable('toArray');
	var listString = listElems.join(";");
	var modeElem = document.getElementById(inputID);
	modeElem.value = listString;
	return true;
}

// set ckeditor basepath
var CVCEDITOR_BASEPATH = '' + '/static/cvceditor/';


// sleep time expects milliseconds
//function sleep (time) {
//  return new Promise((resolve) => setTimeout(resolve, time));
//}


// Usage!
//sleep(500).then(() => {
    // Do something after the sleep!
//});

function loadTTVars(elementid) {
    // load tt vars from mask template (if defined)
    if(!$(elementid).length) {
        return;
    }

    var maskttvars = $(elementid).data();
    for(var key in maskttvars) {
        if(key.substring(0, 7) == "trquote") {
            var trkey = key.substring(7);
            if(trkey in ttvars['trquote']) {
                console.log("Warning: Overwriting " + trkey + " in ttvars.trquote");
            }
            ttvars['trquote'][trkey] = maskttvars[key];
        } else if(key.substring(0, 4) == "json") {
            var jsonkey = key.substring(4);
            var jsonheader = maskttvars[key].substring(0, 5);
            if(jsonheader != 'JSON:') {
                console.log("ERROR: tt var " + key + " does not begin with 'JSON:'");
                continue;
            }
            
            if(jsonkey in ttvars['json']) {
                console.log("Warning: Overwriting " + jsonkey + " in ttvars.json");
            }
            var jsonraw = maskttvars[key].substring(5);
            if(jsonraw === "") {
                continue;
            }
            var jsonparsed = JSON.parse(jsonraw);
            ttvars['json'][jsonkey] = jsonparsed;
        } else {
            if(key in ttvars) {
                console.log("Warning: Overwriting " + key + " in ttvars");
            }
            ttvars[key] = maskttvars[key];
        }
    }
}

// Stupidly simple try to disambiguate people from robots
var _romocnt = 0;
var _romostate = '';

function romoCalc() {
    if(_romostate === '') {
        _romostate = document.getElementById('tempsessionid').value;
    }
    _romocnt++;
    if(_romocnt < 20) {
        _romostate = sha256_digest(_romostate.substring(1, 13) + _romocnt);
    } else if(_romocnt === 20) {
        document.getElementById('tempclientid').value = _romostate.substring(3, 11).toUpperCase();
        if(window.romoCallback) {
            romoCallback();
        }
    }

    return;
}

function romoTest() {
    document.addEventListener('mousemove', romoCalc);
    document.addEventListener('touchstart', romoCalc);
    document.addEventListener('touchend', romoCalc);
    document.addEventListener('touchcancel', romoCalc);
    document.addEventListener('touchmove', romoCalc);
    
    return;
}
