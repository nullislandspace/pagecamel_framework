import { InitSqlJsStatic } from "sql.js";
declare const initSqlJs: InitSqlJsStatic;
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
export declare class PCSqlite {
    private _db;
    private _autocommit;
    private _dbloaded;
    private _isdebug;
    private _dbname;
    private _promiseInitialize;
    private _SQL;
    private _binWorker;
    private _dbVersion;
    private _saveToExternalStorage;
    private _loadFromExternalStorage;
    private _multiinsertstmt;
    private _currentSaveID;
    private _seenSaveID;
    constructor({ config, dbname, debug, saveToExternalStorage, loadFromExternalStorage, }: {
        config: initSqlJs.SqlJsConfig;
        dbname?: string;
        debug?: boolean;
        saveToExternalStorage?: (data: string) => void;
        loadFromExternalStorage?: () => Promise<string>;
    });
    get dbstring(): string;
    get initialize(): Promise<string>;
    get db(): initSqlJs.Database | null;
    set autocommit(ac: boolean);
    private _initialize;
    private _SQLtoBinArray;
    private _SQLtoBinString;
    private _logdebug;
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
    executeSQL: (statement: string, ...args: string[]) => initSqlJs.ParamsObject[] | null;
    multiInsert_Start: (statement: string) => initSqlJs.ParamsObject[] | null;
    multiInsert_End: () => initSqlJs.ParamsObject[] | null;
    multiInsert_Execute: (...args: string[]) => initSqlJs.ParamsObject[] | null;
    /**
     * Save the DB from memory to IndexedDB
     *
     * @param data - Serialized database string
     *
     */
    private _saveToIndexedDB;
    /**
     * Load the DB from IndexedDB
     *
     * @returns Serialized database string or null
     *
     */
    private _loadFromIndexedDB;
    save(): void;
    /**
     * Reset the database and create a new one
     *
     * @returns True if a new database was createed
     */
    reset(): boolean;
    isAllSaved(): boolean;
}
export {};
//# sourceMappingURL=sqlite.d.ts.map