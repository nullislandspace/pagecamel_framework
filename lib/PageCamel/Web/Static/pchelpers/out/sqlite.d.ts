import { InitSqlJsStatic } from "sql.js";
declare const initSqlJs: InitSqlJsStatic;
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
    constructor(config: initSqlJs.SqlJsConfig, dbname?: string, debug?: boolean);
    get dbstring(): string;
    get initialize(): Promise<string>;
    get db(): initSqlJs.Database | null;
    set autocommit(ac: boolean);
    private _initialize;
    private _SQLtoBinArray;
    private _SQLtoBinString;
    private _logdebug;
    executeSQL: (statement: string, ...args: string[]) => initSqlJs.ParamsObject[] | null;
    private _saveToIndexedDB;
    private _loadFromIndexedDB;
    save(): void;
    reset(): boolean;
}
export {};
