import { exit } from 'process';
import { InitSqlJsStatic, SqlJsStatic } from 'sql.js';
import { Database } from 'sql.js';
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


    private _db:initSqlJs.Database|null;
    private _dbid:string;
    private _autocommit:boolean;
    private _dbloaded:boolean;
    private _isdebug:boolean;
    private _dbname:string;
    private _promiseInitialize:Promise<string>;
    private _SQL:SqlJsStatic|null;
    
    
    constructor(config:initSqlJs.SqlJsConfig,dbname='',debug=false){
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        this._dbname = dbname;
        this._autocommit = true;
        this._SQL = null;
        this._promiseInitialize = this._initialize(config,dbname);
        this._dbid = 'X'; // Init with invalid ID to force loading DB on startup
    }

    private _randomDBID():string {
        return Date.now().toString() + '_' + (Math.random()*100000).toString();
    }

    
    get dbstring():string {
        if (this._db) {
            var dbstr:string = this._SQLtoBinString(this._db.export());
            return dbstr;
        }
        else {
            return "";
        }
    }

    
    get initialize():Promise<string> {
        return this._promiseInitialize;
    }

    
    set autocommit(ac:boolean) {
        this._autocommit = ac;
    }

    private _initialize(config:initSqlJs.SqlJsConfig,dbname=''):Promise<string> {
        return new Promise((resolve,reject) => {
            if ( (initSqlJs) instanceof Function) {
        
                if (this._isdebug) console.debug("================ sql.js loaded");
            
                
                
            
                initSqlJs(config).then((SQL) => {
                    if (this._isdebug) console.debug("####### PROMISE initSqlJs RESOLVED, PROMISE _initalize CALLED #######");
                    var dbstr:string|null = null;
                    this._SQL = SQL;
                    if (dbname != '') {
                    dbstr = window.localStorage.getItem(dbname);
                    }
                    if (dbstr) {
                        this._db = new SQL.Database(this._SQLtoBinArray(dbstr));
                    } else {
                        this._db = new SQL.Database();
                        this.save();
                    }
                    this._dbloaded = true;
                    if (this._isdebug) console.debug("****  PCSqlite Database loaded ****");
                    resolve("PCSqlite initialized");
                });
            }
            else {
                console.error("========= sql.js not loaded =========");
                reject("sql.js not loaded");
            }
        });
    }

    private _SQLtoBinArray(str:string):Uint8Array {
        var l = str.length,
            arr = new Uint8Array(l);
        for (var i = 0; i < l; i++) {
            arr[i] = str.charCodeAt(i);
        }
        return arr;
    }

    private _SQLtoBinString(arr:Uint8Array):string {
        var uarr = new Uint8Array(arr);
        var strings:string[] = [], chunksize = 0xffff;
        // There is a maximum stack size. We cannot call String.fromCharCode with as many arguments as we want

        //console.log("SQL Backup is " + uarr.length + " bytes large");
        for (var i = 0; i * chunksize < uarr.length; i++) {
            var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
            strings.push(String.fromCharCode.apply(null, numarr));
        }
        //console.log("DB SAVE IS " + strings.length + " bytes long");
        return strings.join('');
    }




    private _logdebug(...args:any[]):void {
        if(!this._isdebug) {
            return;
        }
        args.forEach((val)=>{console.debug(val)});
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
    executeSQL(statement:string, ...args:string[]):initSqlJs.ParamsObject[]|null{
        //statement = 'PRAGMA foreign_keys = ON;' + statement;
        //noerror();
        if (this._db) {
            let results:initSqlJs.ParamsObject[] = [];  
            let stmt:initSqlJs.Statement = this._db.prepare(statement);
            try {
                if(this._isdebug) {
                    console.debug(statement);
                }

                let dbstr:string|null = null;
                if (this._dbname != '') {
                    var storeddbid:string|null = window.localStorage.getItem(this._dbname + '_dbid');
                    if (storeddbid != this._dbid) {
                        this._logdebug("^^^^^  RELOAD DB");
                        dbstr = window.localStorage.getItem(this._dbname);
                        if(dbstr && this._SQL) {
                            this._db = null;
                            this._db = new this._SQL.Database(this._SQLtoBinArray(dbstr));
                            stmt = this._db.prepare(statement);
                            if (storeddbid) {
                                this._dbid = storeddbid;
                            }
                        }
                    } else {
                        this._logdebug("^^^^^  DO NOT RELOAD DB");
                    }
                }
                
                if (stmt.bind(args)) {
                    this._logdebug("Execute statement SQL: " + stmt.getNormalizedSQL());
                    while (stmt.step()) { //
                        var row = stmt.getAsObject();
                        results.push(row);
                        this._logdebug(["row: ", row]);
                    }
                    this._logdebug(["results: ", results]);
                }
                
            } catch (fail) {
                results = [];
                console.error('sqllite error: ', fail);
                results.push(stmt.getAsObject(args));
                //stmt.free();
                //throw new Error(<string>fail);
                
            }
            stmt.free();
            //pagecamelDBSave();
            //Save DB to File only if autocommit is enabled and statement isn't a select query
            if( !statement.match(/^select /i) && this._autocommit) {
                this.save();
            }
            
            return results;
        }
        else { return null};
        
    }

    /**
     * Save the DB from memory to local storage
     *
     * 
     * 
    */
    save():void {
        if (this._db && this._dbname != '') {
            var dbstr = this._SQLtoBinString(this._db.export());
            if (this._isdebug) console.debug("*** save database to " + this._dbname);
            window.localStorage.setItem(this._dbname, dbstr);
            this._dbid = this._randomDBID();
            window.localStorage.setItem(this._dbname + '_dbid', this._dbid);
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
        }
        else {
            console.error("No PCSqlite._SQL object available. Can't create a new database.");
            return false;
        }
        
        
    }


}
