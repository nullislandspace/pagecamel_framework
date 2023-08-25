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
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        this._autocommit = true;
        this._SQL = null;
        this._promiseInitialize = this._initialize(config, dbname);
        this._dbid = "X";
        this._binWorker = new Worker("/static/pchelpers/out/SQLtoBinWorker.js");
        this._binWorker.onmessage = (e) => {
            var command = e.data[0];
            var data = e.data[1];
            if (command == "SAVEDB") {
                if (this._isdebug)
                    console.debug("*** save database to " + this._dbname);
                this._saveToIndexedDB(data);
                this._dbid = this._randomDBID();
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
    set autocommit(ac) {
        this._autocommit = ac;
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
                                yield this.save();
                            }
                            this._dbloaded = true;
                            if (this._isdebug)
                                console.debug("****  PCSqlite Database loaded ****");
                            resolve("PCSqlite initialized");
                        }));
                    }
                    else {
                        this._db = new SQL.Database();
                        yield this.save();
                        this._dbloaded = true;
                        if (this._isdebug)
                            console.debug("****  PCSqlite Database loaded ****");
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
    executeSQL(statement, ...args) {
        if (this._db && this._dbloaded) {
            let results = [];
            let stmt = this._db.prepare(statement);
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
    }
    _saveToIndexedDB(data) {
        var request = window.indexedDB.open("pcsqlite", this._dbVersion);
        request.onerror = function (event) {
            console.error("IndexedDB error: ", event);
        };
        request.onsuccess = function (event) {
            var db = request.result;
            var transaction = db.transaction(["pcsqlite"], "readwrite");
            var objectStore = transaction.objectStore("pcsqlite");
            var putRequest = objectStore.put(data, "id");
            putRequest.onerror = function (event) {
                console.error("IndexedDB error: ", event);
            };
            putRequest.onsuccess = function (event) {
                console.debug("Database saved to IndexedDB");
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
                db.createObjectStore("pcsqlite", { keyPath: "id" });
            };
            request.onsuccess = function (event) {
                const db = request.result;
                const transaction = db.transaction(["pcsqlite"], "readonly");
                const objectStore = transaction.objectStore("pcsqlite");
                const getRequest = objectStore.get(1);
                getRequest.onerror = function (event) {
                    console.error("IndexedDB error: ", event);
                    resolve(null);
                };
                getRequest.onsuccess = function (event) {
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
        return new Promise((resolve, reject) => {
            if (this._db && this._dbname != "") {
                if (this._isdebug)
                    console.debug("*** preparing to save database to " + this._dbname);
                const dbRequest = indexedDB.open(this._dbname, this._dbVersion);
                dbRequest.onerror = (event) => {
                    var _a;
                    console.error("Failed to open database:", (_a = event.target) === null || _a === void 0 ? void 0 : _a.error);
                    reject();
                };
                dbRequest.onupgradeneeded = (event) => {
                    const db = event.target.result;
                    const objectStore = db.createObjectStore(this._dbname, {
                        keyPath: "id",
                    });
                    objectStore.createIndex("id", "id", { unique: true });
                };
                dbRequest.onsuccess = (event) => {
                    var _a;
                    const db = (_a = event.target) === null || _a === void 0 ? void 0 : _a.result;
                    if (!db) {
                        console.error("Failed to open database: db is null");
                        resolve();
                        return;
                    }
                    const transaction = db.transaction(this._dbname, "readwrite");
                    const objectStore = transaction.objectStore(this._dbname);
                    if (this._db === null) {
                        console.error("Failed to save database: this._db is null");
                        resolve();
                        return;
                    }
                    const request = objectStore.put({
                        id: 1,
                        data: this._SQLtoBinString(this._db.export()),
                    });
                    request.onerror = (event) => {
                        var _a;
                        console.error("Failed to save database:", (_a = event.target) === null || _a === void 0 ? void 0 : _a.error);
                        resolve();
                    };
                    request.onsuccess = (event) => {
                        if (this._isdebug)
                            console.debug("*** database saved to IndexedDB");
                        this._dbid = this._randomDBID();
                        window.localStorage.setItem(this._dbname + "_dbid", this._dbid);
                        resolve();
                    };
                    transaction.oncomplete = () => {
                        db.close();
                    };
                };
            }
            else {
                resolve();
            }
        });
    }
    reset() {
        if (this._SQL) {
            this._logdebug("Create new database and save it");
            this._db = new this._SQL.Database();
            return true;
        }
        else {
            console.error("No PCSqlite._SQL object available. Can't create a new database.");
            return false;
        }
    }
}
//# sourceMappingURL=sqlite.js.map