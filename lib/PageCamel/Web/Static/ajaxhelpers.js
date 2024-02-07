var http = false;
var srefresh = false;
var srefreshurl = '';
var srefreshfield = '';

http = new XMLHttpRequest();
srefresh = new XMLHttpRequest();

function ajaxUpdateInputField(FieldButton, FieldName, TargetUrl) {
  FieldButton.disabled = true;
  var myInp = document.getElementById(FieldName);
  myInp.disabled = true;
  http.open("GET", TargetUrl, true);
  http.onreadystatechange=function() {
    if(http.readyState == 4) {
	  myInp.value = http.responseText;
	  myInp.disabled = false;
	  FieldButton.disabled = false;
    }
  }
  http.send(null);
}

function sendSessionRefresh() {
    if(!navigator.sendBeacon) {
        srefresh.open("GET", srefreshurl, true);
        srefresh.onreadystatechange=function() {
            if(srefresh.readyState == 4) {
                console.log("SESSION REFRESH STATUS: " + srefresh.status);
                if(srefresh.status == 200 || srefresh.status == 204) {
                    if(srefresh.responseText == 'INVALID_SESSION') {
                        location.reload(true);
                    }
                }
            }
        }
        srefresh.send(null);
    } else {
        // Use modern BEACONS instead when supported
        navigator.sendBeacon(srefreshurl);
    }
    return;
}

function doSessionRefresh() {
    if(!localStorage.getItem('PageCamelLastSessionRefresh')) {
        localStorage.setItem('PageCamelLastSessionRefresh', 1);
        setTimeout(doSessionRefresh, 30000 + Math.floor(Math.random()*3000));
        sendSessionRefresh();
    } else {
        var lastUpdate = localStorage.getItem('PageCamelLastSessionRefresh');
        var thisUpdate = Math.floor(new Date().getTime() / 1000);
        if((thisUpdate - lastUpdate) < 15) {
            // last update not long enough ago
            setTimeout(doSessionRefresh, 20000 + Math.floor(Math.random()*3000));
            return;
        }
        localStorage.setItem('PageCamelLastSessionRefresh', thisUpdate);
        setTimeout(doSessionRefresh, 20000 + Math.floor(Math.random()*3000));
        sendSessionRefresh();

    }
    return;
}

function startSessionRefresh(FieldName, TargetUrl) {
    srefreshfield = FieldName;
    srefreshurl = TargetUrl;
    if(!navigator.sendBeacon) {
        //console.log("Sessionrefresh via AJAX.");
    } else {
        // Use modern BEACONS instead when supported
        //console.log("Sessionrefresh via BEACON.");
    }
    setTimeout(doSessionRefresh, 30000 + Math.floor(Math.random()*3000));
}

function ajaxSetInputField(FieldName, FieldValue) {
  var myInp = document.getElementById(FieldName);
  myInp.value = FieldValue;
}

function ajaxCheckHideElement(SrcElemName, DestElemName, EnabledValue) {
  var mySrc = document.getElementById(SrcElemName);
  var myDest = document.getElementById(DestElemName);
  if(mySrc.value == EnabledValue) {
	myDest.style.visibility = "visible";
  } else {
	myDest.style.visibility = "hidden";
  }
  return true;
}

function ajaxUpdateInputFieldWithCheck(FieldButton, FieldName, TargetUrl, CheckElemName, CheckValue) {
  FieldButton.disabled = true;
  var myInp = document.getElementById(FieldName);
  myInp.disabled = true;
  http.open("GET", TargetUrl, true);
  http.onreadystatechange=function() {
    if(http.readyState == 4) {
	  myInp.value = http.responseText;
	  myInp.disabled = false;
	  FieldButton.disabled = false;
	  var myDest = document.getElementById(CheckElemName);
	  if(myInp.value == CheckValue) {
		myDest.style.visibility = "visible";
	  } else {
		myDest.style.visibility = "hidden";
	  }
    }
  }
  http.send(null);
}
