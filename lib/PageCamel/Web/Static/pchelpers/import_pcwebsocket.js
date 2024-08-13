/*
* js-file for loading the websocket object into the global window namespace
* don't try to change it to ts-file
*/
import { PCWebsocket } from "./src/websocket.js";
import { onLoadExt } from "./src/test/test_websocket.js";
window.pcws = new PCWebsocket(true, true);


//test_websocket.onLoadExt function
window.test_my_sockets = onLoadExt;
