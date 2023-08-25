/// <reference types="sql.js" />
export declare class PCSqlite {
    private _db;
    private _dbid;
    private _autocommit;
    private _dbloaded;
    private _isdebug;
    private _dbname;
    private _promiseInitialize;
    private _SQL;
    private _binWorker;
    private _dbVersion;
    private _dbStoreName;
    constructor(config: initSqlJs.SqlJsConfig, dbname?: string, debug?: boolean);
    private _randomDBID;
    get dbstring(): string;
    get initialize(): Promise<string>;
    set autocommit(ac: boolean);
    private _initialize;
    private _SQLtoBinArray;
    private _SQLtoBinString;
    private _logdebug;
    executeSQL(statement: string, ...args: string[]): initSqlJs.ParamsObject[] | null;
    private _saveToIndexedDB;
    private _loadFromIndexedDB;
    save(): Promise<void>;
    reset(): boolean;
}
