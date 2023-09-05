/*
 * js-file for loading the websocket object into the global window namespace
 * don't try to change it to ts-file
 */
import { PCSqlite } from "./out/sqlite.js";

var baseUrl = "/static/sqljs/";

// Normally Sql.js tries to load sql-wasm.wasm relative to the page, not relative to the javascript
// doing the loading. So, we help it find the .wasm file with this function.
var fname = baseUrl + "sql-wasm.wasm";
var config = {
    locateFile: (filename) => fname,
};

window.sqlite = new PCSqlite({
    config: config,
    dbname: "pagecamel.sqlite",
    debug: true,
    saveToExternalStorage: window.saveToExternalStorage,
    loadFromExternalStorage: window.loadFromExternalStorage,
});
