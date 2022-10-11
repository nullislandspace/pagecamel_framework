import { exit } from 'process';
//import initSqlJs from 'sql.js';
//import * as SQLDB from './sql-wasm.js';

const initSqlJs = window.initSqlJs;



/**
 * What is the class's single responsibility?
 * @remarks
 *
 * When should use use the class? What performance benefits, functionality, or other magical power does it confer upon you?
 *
 * * When shouldn't you use the class?
 *
 * * What states does this class furnish?
 *
 * * What behaviors does this class furnish?
 *
 * * Can you inject dependencies into this class?
 *
 * * Are there any situations where it makes sense to extend this class, rather than inject dependencies into it?
 *
 * * How does the code in this class work?
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
    private _dbloaded:boolean;
    private _isdebug;
    
    constructor(config:initSqlJs.SqlJsConfig,dbstring='',debug=false){
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        
    }

    save():void {
        if (this._db) {
            var dbstr = this._SQLtoBinString(this._db.export());
            window.localStorage.setItem("pagecamel.sqlite", dbstr);
        }
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

    initialize(config:initSqlJs.SqlJsConfig,dbstring=''):void {
        if ( (initSqlJs) instanceof Function) {
    
            if (this._isdebug) console.debug("================ sql.js loaded");
        
            
            
        
            initSqlJs(config).then((SQL) => {
                if (this._isdebug) console.debug("################## PROMISE CALLED");
                var dbstr:string|null = null;
                if (dbstring != '') {
                dbstr = window.localStorage.getItem(dbstring);
                }
                if (dbstr) {
                    this._db = new SQL.Database(this._SQLtoBinArray(dbstr));
                } else {
                    this._db = new SQL.Database();
                    this.save();
                }
                this._dbloaded = true;
                if (this._isdebug) console.debug("*****************************  PCSqlite Database loaded");
            
            });
        }
        else {
            console.error("========= sql.js not loaded =========");
        }
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

        for (var i = 0; i * chunksize < uarr.length; i++) {
            var numarr = Array.from(uarr.subarray(i * chunksize, (i + 1) * chunksize));
            strings.push(String.fromCharCode.apply(null, numarr));
        }
        return strings.join('');
    }

    executeSQL(statement:string, ...args:any[]):initSqlJs.ParamsObject[]|null{
        //statement = 'PRAGMA foreign_keys = ON;' + statement;
        //noerror();
        if (this._db) {
            var results:initSqlJs.ParamsObject[] = [];
            var stmt:initSqlJs.Statement = this._db.prepare(statement);
            try {
                stmt.bind(args);
                while (stmt.step()) { //
                    var row = stmt.getAsObject();
                    results.push(row);
                }
            } catch (fail) {
                results = [];
                console.error('sqllite error: ', fail);
                results.push(stmt.getAsObject(args));
               
            }
            stmt.free();
            //pagecamelDBSave();
            return results;
        }
        else { return null};
        
    }



}