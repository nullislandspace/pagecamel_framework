"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PCSqlite = void 0;
const initSqlJs = window.initSqlJs;
class PCSqlite {
    _db;
    _autocommit;
    _dbloaded;
    _isdebug;
    _dbname = "pcsqlite";
    _promiseInitialize;
    _SQL;
    _binWorker;
    _dbVersion = 1;
    _saveToExternalStorage = undefined;
    _loadFromExternalStorage = undefined;
    constructor({ config, dbname = "", debug = false, saveToExternalStorage, loadFromExternalStorage, }) {
        this._saveToExternalStorage = saveToExternalStorage;
        this._loadFromExternalStorage = loadFromExternalStorage;
        console.log("loadFromExternalStorage", this._loadFromExternalStorage);
        console.log("saveToExternalStorage", this._saveToExternalStorage);
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        this._dbname = dbname;
        this._autocommit = true;
        this._SQL = null;
        this._promiseInitialize = this._initialize(config);
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
    _initialize(config) {
        return new Promise((resolve, reject) => {
            if (initSqlJs instanceof Function) {
                if (this._isdebug)
                    console.debug("================ sql.js loaded");
                initSqlJs(config).then(async (SQL) => {
                    if (this._isdebug)
                        console.debug("####### PROMISE initSqlJs RESOLVED, PROMISE _initalize CALLED #######");
                    this._SQL = SQL;
                    this._loadFromIndexedDB().then(async (data) => {
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
                            resolve("PCSqlite initialized");
                    });
                });
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
    executeSQL = (statement, ...args) => {
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
    _saveToIndexedDB(data) {
        var request = window.indexedDB.open(this._dbname, this._dbVersion);
        request.onerror = function (event) {
            console.error("IndexedDB error: ", event);
        };
        request.onsuccess = (event) => {
            var db = request.result;
            if (!db.objectStoreNames.contains(this._dbname)) {
                db.close();
                window.indexedDB.deleteDatabase(this._dbname);
                this._logdebug("IndexedDB deleted");
                return;
            }
            const transaction = db.transaction([this._dbname], "readwrite");
            const objectStore = transaction.objectStore(this._dbname);
            const putRequest = objectStore.put({ data: data, id: 1 });
            putRequest.onerror = function (event) {
            };
            putRequest.onsuccess = (event) => {
            };
            transaction.oncomplete = () => {
                db.close();
            };
        };
        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (db.objectStoreNames.contains(this._dbname)) {
                db.deleteObjectStore(this._dbname);
            }
            db.createObjectStore(this._dbname, { keyPath: "id" });
        };
    }
    _loadFromIndexedDB() {
        return new Promise((resolve, reject) => {
            const request = window.indexedDB.open(this._dbname, this._dbVersion);
            request.onerror = function (event) {
                console.error("IndexedDB error: ", event);
                resolve(null);
            };
            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                if (db.objectStoreNames.contains(this._dbname)) {
                    db.deleteObjectStore(this._dbname);
                }
                db.createObjectStore(this._dbname, { keyPath: "id" });
            };
            request.onsuccess = (event) => {
                const db = request.result;
                const transaction = db.transaction([this._dbname], "readonly");
                if (!db.objectStoreNames.contains(this._dbname)) {
                    db.close();
                    window.indexedDB.deleteDatabase(this._dbname);
                    resolve(null);
                    return;
                }
                const objectStore = transaction.objectStore(this._dbname);
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
        this._binWorker.postMessage(["SQLTOSTRING", this._db?.export()]);
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
exports.PCSqlite = PCSqlite;
//# sourceMappingURL=sqlite.js.map