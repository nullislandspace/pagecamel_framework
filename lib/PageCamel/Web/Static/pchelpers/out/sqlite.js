var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
const initSqlJs = window.initSqlJs;
export class PCSqlite {
    constructor(config, dbname = "", debug = false) {
        this._dbname = "pcsqlite";
        this._dbVersion = 1;
        this._dbStoreName = "pcsqlite";
        this._dbid = "";
        this.executeSQL = (statement, ...args) => {
            if (this._db && this._dbloaded) {
                let results = [];
                var stmt = this._db.prepare(statement);
                try {
                    if (stmt.bind(args)) {
                        while (stmt.step()) {
                            var row = stmt.getAsObject();
                            results.push(row);
                        }
                    }
                }
                catch (fail) {
                    results = [];
                    console.error("sqllite error: ", fail);
                    results.push(stmt.getAsObject(args));
                }
                stmt.free();
                if (!statement.match(/^select /i) && this._autocommit) {
                    this.save();
                }
                return results;
            }
            else {
                return null;
            }
        };
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        this._autocommit = true;
        this._SQL = null;
        this._promiseInitialize = this._initialize(config, dbname);
        this._binWorker = new Worker("/static/pchelpers/out/SQLtoBinWorker.js");
        this._binWorker.onmessage = (e) => {
            var command = e.data[0];
            var data = e.data[1];
            if (command == "SAVEDB") {
                if (this._isdebug)
                    console.debug("*** save database to " + this._dbname);
                this._saveToIndexedDB(data);
            }
        };
        this._binWorker.postMessage(["START", ""]);
    }
    _randomDBID() {
        return (Date.now().toString() + "_" + (Math.random() * 100000).toString());
    }
    get dbstring() {
        if (this._db) {
            var dbstr = this._SQLtoBinString(this._db.export());
            return dbstr;
        }
        else {
            return "";
        }
    }
    get initialize() {
        return this._promiseInitialize;
    }
    get db() {
        return this._db;
    }
    set autocommit(ac) {
        this._autocommit = ac;
    }
    _getDBID() {
        var dbid = window.localStorage.getItem(this._dbStoreName + "_dbid");
        if (dbid) {
            this._dbid = dbid;
        }
        else {
            this._dbid = this._randomDBID();
            window.localStorage.setItem(this._dbStoreName + "_dbid", this._dbid);
        }
        return this._dbid;
    }
    _initialize(config, dbname = "") {
        return new Promise((resolve, reject) => {
            if (initSqlJs instanceof Function) {
                if (this._isdebug)
                    console.debug("================ sql.js loaded");
                initSqlJs(config).then((SQL) => __awaiter(this, void 0, void 0, function* () {
                    if (this._isdebug)
                        console.debug("####### PROMISE initSqlJs RESOLVED, PROMISE _initalize CALLED #######");
                    var dbstr = null;
                    this._SQL = SQL;
                    if (dbname != "") {
                        this._loadFromIndexedDB().then((data) => __awaiter(this, void 0, void 0, function* () {
                            if (data) {
                                var decompressed = LZString.decompress(data);
                                this._db = new SQL.Database(this._SQLtoBinArray(decompressed));
                            }
                            else {
                                this._db = new SQL.Database();
                                this.save();
                            }
                            this._dbloaded = true;
                            if (this._isdebug)
                                console.debug("****  PCSqlite Database loaded ****");
                            this._dbid = this._getDBID();
                            resolve("PCSqlite initialized");
                        }));
                    }
                    else {
                        this._db = new SQL.Database();
                        this.save();
                        this._dbloaded = true;
                        if (this._isdebug)
                            console.debug("****  PCSqlite Database loaded ****");
                        this._dbid = this._getDBID();
                        resolve("PCSqlite initialized");
                    }
                }));
            }
            else {
                console.error("========= sql.js not loaded =========");
                reject("sql.js not loaded");
            }
        });
    }
    _SQLtoBinArray(str) {
        var l = str.length, arr = new Uint8Array(l);
        for (var i = 0; i < l; i++) {
            arr[i] = str.charCodeAt(i);
        }
        return arr;
    }
    _SQLtoBinString(arr) {
        var uarr = new Uint8Array(arr);
        var strings = [], chunksize = 0xffff;
        for (var i = 0; i * chunksize < uarr.length; i++) {
            var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
            strings.push(String.fromCharCode.apply(null, numarr));
        }
        return strings.join("");
    }
    _logdebug(...args) {
        if (!this._isdebug) {
            return;
        }
        args.forEach((val) => {
            console.debug(val);
        });
    }
    _saveToIndexedDB(data) {
        var request = window.indexedDB.open("pcsqlite", this._dbVersion);
        request.onerror = function (event) {
            console.error("IndexedDB error: ", event);
        };
        request.onsuccess = (event) => {
            const db = request.result;
            const transaction = db.transaction(["pcsqlite"], "readwrite");
            const objectStore = transaction.objectStore("pcsqlite");
            const putRequest = objectStore.put({ data: data, id: 1 });
            putRequest.onerror = function (event) {
                console.error("IndexedDB error: ", event);
            };
            putRequest.onsuccess = (event) => {
                const dbid = this._randomDBID();
                this._dbid = dbid;
                window.localStorage.setItem(this._dbStoreName + "_dbid", dbid);
                console.debug("Database saved to IndexedDB");
            };
            transaction.oncomplete = () => {
                db.close();
            };
        };
    }
    _loadFromIndexedDB() {
        return new Promise((resolve, reject) => {
            const request = window.indexedDB.open("pcsqlite", this._dbVersion);
            request.onerror = function (event) {
                console.error("IndexedDB error: ", event);
                resolve(null);
            };
            request.onupgradeneeded = function (event) {
                const db = event.target.result;
                if (db.objectStoreNames.contains("pcsqlite")) {
                    db.deleteObjectStore("pcsqlite");
                }
                db.createObjectStore("pcsqlite", { keyPath: "id" });
            };
            request.onsuccess = (event) => {
                const db = request.result;
                const transaction = db.transaction(["pcsqlite"], "readonly");
                const objectStore = transaction.objectStore("pcsqlite");
                const getRequest = objectStore.get(1);
                getRequest.onerror = function (event) {
                    console.error("IndexedDB error: ", event);
                    resolve(null);
                };
                getRequest.onsuccess = (event) => {
                    if (getRequest.result) {
                        console.debug("Database loaded from IndexedDB");
                        resolve(getRequest.result.data);
                    }
                    else {
                        resolve(null);
                    }
                };
            };
        });
    }
    save() {
        var _a;
        this._binWorker.postMessage(["SQLTOSTRING", (_a = this._db) === null || _a === void 0 ? void 0 : _a.export()]);
    }
    reset() {
        if (this._SQL) {
            this._logdebug("Create new database and save it");
            this._db = new this._SQL.Database();
            this.save();
            return true;
        }
        else {
            console.error("No PCSqlite._SQL object available. Can't create a new database.");
            return false;
        }
    }
}
//# sourceMappingURL=sqlite.js.map