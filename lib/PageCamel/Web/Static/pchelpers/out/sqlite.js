const initSqlJs = window.initSqlJs;
export class PCSqlite {
    constructor(config, dbname = "", debug = false) {
        this._versionNumber = 2;
        this._dbloaded = false;
        this._isdebug = debug;
        this._db = null;
        this._dbname = dbname;
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
                window.localStorage.setItem(this._dbname + '_compressed', data);
                this._dbid = this._randomDBID();
                window.localStorage.setItem(this._dbname + "_dbid", this._dbid);
            }
        };
        this._binWorker.postMessage(["START", '']);
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
            if (this._versionNumber > Number(window.localStorage.getItem('versionNumber'))) {
                console.log("Clearing local storage");
                window.localStorage.clear();
                console.log("Setting version number to " + this._versionNumber.toString());
                window.localStorage.setItem('versionNumber', this._versionNumber.toString());
            }
            if (initSqlJs instanceof Function) {
                if (this._isdebug)
                    console.debug("================ sql.js loaded");
                initSqlJs(config).then((SQL) => {
                    if (this._isdebug)
                        console.debug("####### PROMISE initSqlJs RESOLVED, PROMISE _initalize CALLED #######");
                    var dbstr = null;
                    this._SQL = SQL;
                    if (dbname != "") {
                        dbstr = window.localStorage.getItem(dbname + '_compressed');
                    }
                    if (dbstr) {
                        var decompressed = LZString.decompress(dbstr);
                        this._db = new SQL.Database(this._SQLtoBinArray(decompressed));
                    }
                    else {
                        this._db = new SQL.Database();
                        this.save();
                    }
                    this._dbloaded = true;
                    if (this._isdebug)
                        console.debug("****  PCSqlite Database loaded ****");
                    resolve("PCSqlite initialized");
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
    executeSQL(statement, ...args) {
        if (this._db) {
            let results = [];
            let stmt = this._db.prepare(statement);
            try {
                let dbstr = null;
                if (this._dbname != "") {
                    var storeddbid = window.localStorage.getItem(this._dbname + "_dbid");
                    if (storeddbid != this._dbid) {
                        dbstr = window.localStorage.getItem(this._dbname);
                        if (dbstr && this._SQL) {
                            this._db = null;
                            this._db = new this._SQL.Database(this._SQLtoBinArray(dbstr));
                            stmt = this._db.prepare(statement);
                            if (storeddbid) {
                                this._dbid = storeddbid;
                            }
                        }
                    }
                    else {
                    }
                }
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
    save() {
        if (this._db && this._dbname != "") {
            if (this._isdebug)
                console.debug("*** preparing to save database to " + this._dbname);
            this._binWorker.postMessage(["SQLTOSTRING", this._db.export()]);
        }
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
//# sourceMappingURL=sqlite.js.map