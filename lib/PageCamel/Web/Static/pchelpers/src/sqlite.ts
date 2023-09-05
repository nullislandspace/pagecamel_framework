import { exit } from "process";
import { InitSqlJsStatic, SqlJsStatic } from "sql.js";
import { Database } from "sql.js";
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
    private _db: initSqlJs.Database | null;
    private _autocommit: boolean;
    private _dbloaded: boolean;
    private _isdebug: boolean;
    private _dbname: string = "pcsqlite";
    private _promiseInitialize: Promise<string>;
    private _SQL: SqlJsStatic | null;
    private _binWorker: Worker;
    private _dbVersion: number = 1;
    private _saveToExternalStorage: ((data: string) => void) | undefined =
        undefined;
    private _loadFromExternalStorage:
        | (() => Promise<string | null>)
        | undefined = undefined;

    constructor({
        config,
        dbname = "",
        debug = false,
        saveToExternalStorage,
        loadFromExternalStorage,
    }: {
        config: initSqlJs.SqlJsConfig;
        dbname?: string;
        debug?: boolean;
        saveToExternalStorage?: (data: string) => void;
        loadFromExternalStorage?: () => Promise<string>;
    }) {
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

        this._binWorker.onmessage = (e: MessageEvent): void => {
            var command = e.data[0] as string;
            var data = e.data[1] as string;

            if (command == "SAVEDB") {
                if (this._isdebug)
                    console.debug("*** save database to " + this._dbname);
                this._saveToIndexedDB(data);
            }
        };
        this._binWorker.postMessage(["START", ""]);
    }

    get dbstring(): string {
        if (this._db) {
            var dbstr: string = this._SQLtoBinString(this._db.export());
            return dbstr;
        } else {
            return "";
        }
    }

    get initialize(): Promise<string> {
        return this._promiseInitialize;
    }
    get db(): initSqlJs.Database | null {
        return this._db;
    }

    set autocommit(ac: boolean) {
        this._autocommit = ac;
    }
    private _initialize(config: initSqlJs.SqlJsConfig): Promise<string> {
        return new Promise((resolve, reject) => {
            if (initSqlJs instanceof Function) {
                if (this._isdebug)
                    console.debug("================ sql.js loaded");

                initSqlJs(config).then(async (SQL) => {
                    if (this._isdebug)
                        console.debug(
                            "####### PROMISE initSqlJs RESOLVED, PROMISE _initalize CALLED #######"
                        );
                    this._SQL = SQL;
                    // either get from Mobile Device or load from IndexedDB
                    if (this._loadFromExternalStorage) {
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
                    } else {
                        this._loadFromIndexedDB().then(async (data) => {
                            if (data) {
                                var decompressed = LZString.decompress(data);
                                this._db = new SQL.Database(
                                    this._SQLtoBinArray(decompressed)
                                );
                            } else {
                                this._db = new SQL.Database();
                                this.save();
                            }
                            this._dbloaded = true;
                            if (this._isdebug) resolve("PCSqlite initialized");
                        });
                    }
                });
            } else {
                console.error("========= sql.js not loaded =========");
                reject("sql.js not loaded");
            }
        });
    }

    private _SQLtoBinArray(str: string): Uint8Array {
        var l = str.length,
            arr = new Uint8Array(l);
        for (var i = 0; i < l; i++) {
            arr[i] = str.charCodeAt(i);
        }
        return arr;
    }

    private _SQLtoBinString(arr: Uint8Array): string {
        var uarr = new Uint8Array(arr);
        var strings: string[] = [],
            chunksize = 0xffff;
        for (var i = 0; i * chunksize < uarr.length; i++) {
            var numarr = Array.from(
                uarr.subarray(i * chunksize, (i + 1) * chunksize)
            );
            strings.push(String.fromCharCode.apply(null, numarr));
        }
        return strings.join("");
    }

    private _logdebug(...args: any[]): void {
        if (!this._isdebug) {
            return;
        }
        args.forEach((val) => {
            console.debug(val);
        });
    }

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
    executeSQL = (
        statement: string,
        ...args: string[]
    ): initSqlJs.ParamsObject[] | null => {
        //statement = 'PRAGMA foreign_keys = ON;' + statement;
        //noerror();
        if (this._db && this._dbloaded) {
            let results: initSqlJs.ParamsObject[] = [];
            var stmt: initSqlJs.Statement = this._db.prepare(statement);
            try {
                if (stmt.bind(args)) {
                    while (stmt.step()) {
                        var row = stmt.getAsObject();
                        results.push(row);
                    }
                }
            } catch (fail) {
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
        } else {
            return null;
        }
    };

    /**
     * Save the DB from memory to IndexedDB
     *
     * @param data - Serialized database string
     *
     */
    private _saveToIndexedDB(data: string): void {
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
        request.onupgradeneeded = (event: any) => {
            const db = event.target.result as IDBDatabase;
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
    private _loadFromIndexedDB(): Promise<string | null> {
        return new Promise((resolve, reject) => {
            const request = window.indexedDB.open(
                this._dbname,
                this._dbVersion
            );

            request.onerror = function (event) {
                console.error("IndexedDB error: ", event);
                resolve(null);
            };

            request.onupgradeneeded = (event: any) => {
                const db = event.target.result as IDBDatabase;
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
                    } else {
                        resolve(null);
                    }
                };
            };
        });
    }

    save(): void {
        if (this._saveToExternalStorage) {
            this._saveToExternalStorage(this.dbstring);
        } else {
            this._binWorker.postMessage(["SQLTOSTRING", this._db?.export()]);
        }
    }
    /**
     * Reset the database and create a new one
     *
     * @returns True if a new database was createed
     */
    reset(): boolean {
        if (this._SQL) {
            this._logdebug("Create new database and save it");
            this._db = new this._SQL.Database();
            this.save();
            return true;
        } else {
            console.error(
                "No PCSqlite._SQL object available. Can't create a new database."
            );
            return false;
        }
    }
    /**
     * Method to save the database to a file on the mobile device
     */
    set saveToExternalStorage(func: ((data: string) => void) | undefined) {
        this._saveToExternalStorage = func;
    }
    get saveToExternalStorage(): ((data: string) => void) | undefined {
        return this._saveToExternalStorage;
    }
    /**
     * Method to get the database from a file on the mobile device
     */
    set loadFromExternalStorage(
        func: (() => Promise<string | null>) | undefined
    ) {
        console.log("loadFromExternalStorage", func);
        this._loadFromExternalStorage = func;
        if (this._loadFromExternalStorage) {
            this._loadFromExternalStorage().then((data) => {
                console.log("loadFromExternalStorage Data:", data);
            });
        }
    }
    get loadFromExternalStorage(): (() => Promise<string | null>) | undefined {
        return this._loadFromExternalStorage;
    }
}
