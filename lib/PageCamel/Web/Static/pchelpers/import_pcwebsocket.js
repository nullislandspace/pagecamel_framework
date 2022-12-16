/*
* js-file for loading the websocket object into the global window namespace
* don't try to change it to ts-file
*/
import { PCWebsocket } from "./out/websocket.js";
import { onLoadExt } from "./out/test/test_websocket.js";
window.pcws = new PCWebsocket(true, true);


//test_websocket.onLoadExt function
window.test_my_sockets = onLoadExt;
