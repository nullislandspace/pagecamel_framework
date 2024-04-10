/// <reference types="sql.js" />
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
    executeSQL: (statement: string, ...args: string[]) => initSqlJs.ParamsObject[] | null;
    multiInsert_Start: (statement: string) => initSqlJs.ParamsObject[] | null;
    multiInsert_End: () => initSqlJs.ParamsObject[] | null;
    multiInsert_Execute: (...args: string[]) => initSqlJs.ParamsObject[] | null;
    private _saveToIndexedDB;
    private _loadFromIndexedDB;
    save(): void;
    reset(): boolean;
    isAllSaved(): boolean;
}
//# sourceMappingURL=sqlite.d.ts.map