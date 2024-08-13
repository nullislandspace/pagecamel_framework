//import initSqlJs from 'sql.js';
//import * as SQLDB from './sql-wasm.js';
const initSqlJs = window.initSqlJs;
/**
 * Sqlite database connection class
 * @remarks
 *
 * Use this class to create and connect to a local sqlite database
 *
 * * This class can store a database in a window string or in memory
 *
 * @example
 * ```typescript
 *    //example of how to use this class here
 * ```
 *
 * @alpha @beta @eventProperty @experimental @internal @override @packageDocumentation @public @readonly @sealed @virtual
 */
export class PCSqlite {
    constructor({ config, dbname = "", debug = false, saveToExternalStorage, loadFromExternalStorage, }) {
        this._dbname = "pcsqlite";
        this._dbVersion = 1;
        this._saveToExternalStorage = undefined;
        this._loadFromExternalStorage = undefined;
        this._currentSaveID = 0;
        this._seenSaveID = 0;
        /**
         * Executes an sql statement and returns a result array or NULL
         *
         * @param statement - SQL Statement (with placeholders for parameters)
         * @param args - Array of parameters to bind to the statement (instead placeholder)
         *
         * @returns Rows of result objects or NULL (no results for the sql statement execution)
         * @throws executeSQL error
         *
         */
        this.executeSQL = (statement, ...args) => {
            //statement = 'PRAGMA foreign_keys = ON;' + statement;
            //noerror();
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
                //Save DB to File only if autocommit is enabled and statement isn't a select query
                if (!statement.match(/^select /i) && this._autocommit) {
                    this.save();
                }
                return results;
            }
            else {
                return null;
            }
        };
        this.multiInsert_Start = (statement) => {
            //statement = 'PRAGMA foreign_keys = ON;' + statement;
            //noerror();
            if (this._db && this._dbloaded) {
                var stmt = this._db.prepare(statement);
                this._multiinsertstmt = stmt;
            }
            return null;
        };
        this.multiInsert_End = () => {
            //statement = 'PRAGMA foreign_keys = ON;' + statement;
            //noerror();
            if (this._db && this._dbloaded && this._multiinsertstmt != null) {
                this._multiinsertstmt.free();
                this._multiinsertstmt = null;
                if (this._autocommit) {
                    this.save();
                }
            }
            return null;
        };
        this.multiInsert_Execute = (...args) => {
            //statement = 'PRAGMA foreign_keys = ON;' + statement;
            //noerror();
            if (this._db && this._dbloaded) {
                try {
                    if (this._multiinsertstmt.bind(args)) {
                        while (this._multiinsertstmt.step()) {
                            //var row = stmt.getAsObject();
                            //results.push(row);
                        }
                    }
                }
                catch (fail) {
                    console.error("sqllite error: ", fail);
                    //results.push(stmt.getAsObject(args));
                }
            }
            return null;
        };
        this._saveToExternalStorage = saveToExternalStorage;
        this._loadFromExternalStorage = loadFromExternalStorage;
        //console.log("loadFromExternalStorage", this._loadFromExternalStorage);
        //console.log("saveToExternalStorage", this._saveToExternalStorage);
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        this._dbname = dbname;
        this._autocommit = true;
        this._SQL = null;
        this._promiseInitialize = this._initialize(config);
        this._binWorker = new Worker("/static/pchelpers/src/SQLtoBinWorker.js");
        this._binWorker.onmessage = (e) => {
            var command = e.data[0];
            var data = e.data[1];
            if (command == "SAVEDB") {
                if (this._isdebug)
                    console.debug("*** save database to " + this._dbname);
                this._seenSaveID = e.data[2];
                if (this._seenSaveID == this._currentSaveID) {
                    //console.log("Saving latest database version " + this._seenSaveID);
                }
                else {
                    //console.log("Saving intermediate database version " + this._seenSaveID);
                }
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
                    // either get from Mobile Device or load from IndexedDB
                    /* if (this._loadFromExternalStorage) {
                        var data = await this._loadFromExternalStorage();
                        if (data) {
                            this._db = new SQL.Database(
                                this._SQLtoBinArray(data)
                            );
                        } else {
                            this._db = new SQL.Database();
                            this.save();
                        }
                        this._dbloaded = true;
                        if (this._isdebug) resolve("PCSqlite initialized");
                    } else { */
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
                    // }
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
    /**
     * Save the DB from memory to IndexedDB
     *
     * @param data - Serialized database string
     *
     */
    _saveToIndexedDB(data) {
        var request = window.indexedDB.open(this._dbname, this._dbVersion);
        request.onerror = function (event) {
            console.error("IndexedDB error: ", event);
        };
        request.onsuccess = (event) => {
            var db = request.result;
            // check if object store exists
            if (!db.objectStoreNames.contains(this._dbname)) {
                // if not delete the database
                db.close();
                window.indexedDB.deleteDatabase(this._dbname);
                this._logdebug("IndexedDB deleted");
                return;
            }
            const transaction = db.transaction([this._dbname], "readwrite");
            const objectStore = transaction.objectStore(this._dbname);
            const putRequest = objectStore.put({ data: data, id: 1 });
            putRequest.onerror = function (event) {
                // console.error("IndexedDB error: ", event);
            };
            putRequest.onsuccess = (event) => {
                // console.debug("Database saved to IndexedDB");
            };
            transaction.oncomplete = () => {
                db.close();
            };
        };
        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            // remove the old store
            if (db.objectStoreNames.contains(this._dbname)) {
                db.deleteObjectStore(this._dbname);
            }
            db.createObjectStore(this._dbname, { keyPath: "id" });
        };
    }
    /**
     * Load the DB from IndexedDB
     *
     * @returns Serialized database string or null
     *
     */
    _loadFromIndexedDB() {
        return new Promise((resolve, reject) => {
            const request = window.indexedDB.open(this._dbname, this._dbVersion);
            request.onerror = function (event) {
                console.error("IndexedDB error: ", event);
                resolve(null);
            };
            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                // remove the old store
                if (db.objectStoreNames.contains(this._dbname)) {
                    db.deleteObjectStore(this._dbname);
                }
                db.createObjectStore(this._dbname, { keyPath: "id" });
            };
            request.onsuccess = (event) => {
                const db = request.result;
                // check if object store exists
                const transaction = db.transaction([this._dbname], "readonly");
                // check if object store exists
                if (!db.objectStoreNames.contains(this._dbname)) {
                    // if not delete the database
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
        var _a;
        /*  if (this._saveToExternalStorage) {
            this._saveToExternalStorage(this.dbstring);
        } else { */
        this._currentSaveID++;
        this._binWorker.postMessage(["SQLTOSTRING", (_a = this._db) === null || _a === void 0 ? void 0 : _a.export(), this._currentSaveID]);
        // }
    }
    /**
     * Reset the database and create a new one
     *
     * @returns True if a new database was createed
     */
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
    isAllSaved() {
        if (this._currentSaveID == this._seenSaveID) {
            return true;
        }
        return false;
    }
}
