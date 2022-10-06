import { PCWebsocket } from "./out/websocket.js";
import { onLoadExt } from "./out/test/test_websocket.js";
window.pcws = new PCWebsocket(false, true);



window.test_my_sockets = onLoadExt;