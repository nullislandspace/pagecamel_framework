import { PCSqlite } from "./sqlite.js";

interface CallbackType {
    (messagename: string, data: string): void;
}

declare function wstransmit(msgname: string, data: string, msgid?: string): any;

interface CallbackList {
    messagename: string;
    callbacks: CallbackType[];
}

/**
 * Websocket connection class
 * @remarks
 *
 * Use this class to communicate over a websocket.
 *
 * * Register some callback-functions for special messagenames/messagetypes.
 *
 * * Use send() to send data to the server
 * * There are some special messagetypes:
 * * * ISCONNECTED ... this messagetype informs about the websocket connection status
 * * * RECIEVED ... this messagetype commits the receiving of a cached message
 *
 * @example
 * Register first and get the connection status at register
 * // Adds the getConnectionStatus to "ISCONNECTED"-messagetype an calls the new registered functions with data='1' or '0'
 * function getConnectionStatus(msgname:string, data:string):void{ console.log("Status=" + data)};
 * pw = new PCWebsocket();
 * pw.register("ISCONNECTED", [getConnectionStatus]);
 *
 *
 */
export class PCWebsocket {
    //is the server connection established
    private _isconnected;
    private _isdebug;
    private _iscaching;

    //holds the callback messages and functions
    private _messageList: CallbackList[] = [];

    //timer delta time in seconds
    private _deltatime: number = 250;

    private _cached_msgs: { msg: string; data: string; id: string }[];
    private _last_cached_id: number;
    private _timer: number;
    private _last_cache_sent: number;
    //Cache send delta time in ms
    private _cache_delta_time: number = 5000;

    //database object
    private _db: PCSqlite | null;
    private _dbtable: string;
    private _dbcaching: boolean;
    private _createtablesql: string;
    private _getrowsql: string;
    private _deleterowsql: string;
    private _insertrowsql: string;
    private _countcacheditemssql: string;
    private _droptablesql: string;

    //internal operation messages
    private _msgoutboxempty: string = "OUTBOXEMPTY";
    private _msgrecieved: string = "RECIEVED";
    private _msgisconnected: string = "ISCONNECTED";

    /**
     * Constructor for class
     * @param caching - enable database caching
     * @param debug - use console debuging
     *
     */
    constructor(caching = false, debug = false) {
        this._iscaching = caching;
        this._isdebug = debug;
        this._isconnected = false;
        //db init
        this._db = null;
        this._dbtable = "wstransmit_" + Date.now().toString();
        this._dbtable = "wstransmit";
        this._createtablesql =
            "CREATE TABLE IF NOT EXISTS " +
            this._dbtable +
            " (time INT, msg TEXT, data TEXT);";
        //this._createdbsql="CREATE TABLE IF NOT EXISTS " + this._dbtable + " (msg TEXT, data TEXT);";
        this._droptablesql = "DROP TABLE " + this._dbtable + ";";
        this._getrowsql =
            "SELECT CAST(rowid as text) || '_' || CAST(time as text) AS dbid, msg, data FROM " +
            this._dbtable +
            " ORDER BY time,rowid LIMIT 1;";
        //this._getrowsql="SELECT rowid, msg, data FROM " + this._dbtable + " ORDER BY rowid LIMIT 1;";
        this._deleterowsql =
            "DELETE FROM " +
            this._dbtable +
            " WHERE CAST(rowid as text) || '_' || CAST(time as text) = ?;";
        //this._insertrowsql="INSERT INTO " + this._dbtable + "(time, msg, data) VALUES (strftime('%f','now'),?, ?);";
        this._insertrowsql =
            "INSERT INTO " +
            this._dbtable +
            "(time, msg, data) VALUES ((strftime('%s','now') || substr(strftime('%f','now'),4)),?, ?);";
        //this._insertrowsql="INSERT INTO " + this._dbtable + "(msg, data) VALUES (?, ?);";
        this._countcacheditemssql =
            "SELECT count(*) as num FROM " + this._dbtable + ";";

        this._messageList = [];
        //this._deltatime=1000; //milliseconds
        this._cached_msgs = [];
        this._last_cached_id = 0;
        this._last_cache_sent = 0;
        this._dbcaching = false;
        //start timer
        //this._timer=setInterval(()=>this._timerfunc,this._deltatime);
        this._timer = window.setInterval(() => {
            this._timerfunc();
        }, this._deltatime);
        //this._timer = 0;
    }

    /**
     * Register the callbacks to a messagename
     *
     * @param msgname - messagename to register the callbacks
     * @param callback - Callback-Functions
     *
     *
     */
    register(msgname: string, callback: CallbackType[]): void {
        msgname = msgname.toUpperCase();
        let msgexist = false;
        if (this._messageList.length == 0) {
            if (this._isdebug)
                callback.forEach(function (fct) {
                    console.debug(
                        "Register " + fct.name + " to messagename " + msgname
                    );
                });
            this._messageList.push({
                messagename: msgname,
                callbacks: callback,
            });
        } else {
            for (let i = 0; i < this._messageList.length; i++) {
                //first check if msgname exists
                if (this._messageList[i].messagename === msgname) {
                    msgexist = true;
                    //then check if callback function exists at msgname
                    for (let j = 0; j < callback.length; j++) {
                        if (
                            this._messageList[i].callbacks.includes(callback[j])
                        ) {
                            console.info(
                                "Callback " +
                                    callback[j].name +
                                    " already registered"
                            );
                        } else {
                            this._logdebug(
                                "Register " +
                                    callback[j].name +
                                    " to messagename " +
                                    msgname
                            );
                            this._messageList[i].callbacks.push(callback[j]);
                        }
                    }
                }
            }
            //add callback to new msgname if msgname doesn't exist
            if (!msgexist) {
                if (this._isdebug)
                    callback.forEach(function (fct) {
                        console.debug(
                            "Register " +
                                fct.name +
                                " to messagename " +
                                msgname
                        );
                    });
                this._messageList.push({
                    messagename: msgname,
                    callbacks: callback,
                });
            }
        }
        if (msgname === this._msgisconnected && !msgexist) {
            //call the callbackfunction for ISCONNECTED at register to get the first isconnected status
            this._handleMsg(
                { messagename: msgname, callbacks: callback },
                msgname,
                this._isconnected ? "1" : "0"
            );
        }
    }

    /**
     * Deregister the callbacks from a messagename
     *
     * @param name - messagename
     * @param callback - Callback-Functions
     *
     */
    deregister(msgname: string, callback: CallbackType[]): void {
        msgname = msgname.toUpperCase();
        if (this._messageList.length === 0) {
            console.log("No callback in the callbacklist");
        } else {
            let msgexist = false;
            for (let i = 0; i < this._messageList.length; i++) {
                //first check if msgname exists
                if (this._messageList[i].messagename === msgname) {
                    msgexist = true;
                    //search remove the callbacks
                    let cindex = 0;
                    for (let c = 0; c < callback.length; c++) {
                        cindex = this._messageList[i].callbacks.indexOf(
                            callback[c]
                        );
                        if (cindex > -1) {
                            this._logdebug(
                                "Deregister callback=" +
                                    callback +
                                    " on messagename=" +
                                    msgname
                            );
                            this._messageList[i].callbacks.splice(cindex, 1);
                        }
                    }
                    //check if messagename has any callbacks
                    if (this._messageList[i].callbacks.length === 0) {
                        //remove messagename from messagelist if no callbacks exist
                        this._messageList.splice(i, 1);
                    }
                }
            }
            if (!msgexist) {
                this._logdebug(
                    "No deregister: the messagename: " +
                        msgname +
                        " does not exist"
                );
            }
        }
    }

    /**
     * Send the message over the websocket
     *
     * @param msgname - Name of the websocket message
     * @param mdata - Message data
     * @param caching - Cache this message if message caching is enabled (see constructor -> caching)
     *
     * @returns TRUE if message is sent or cached
     *
     */
    send(msgname: string, mdata: string, caching = false): boolean {
        msgname = msgname.toUpperCase();
        let sent = false;
        if (this._iscaching && caching) {
            //increment last cached id
            //++this._last_cached_id;
            //cache the message
            this._logdebug("Add message to cache: msgname=" + msgname);
            //this._cached_msgs.push({msg:msgname,data:mdata,id:this._last_cached_id.toString()});
            try {
                if (this._db && this._dbcaching) {
                    //let str = "INSERT INTO " + this._dbtable + "(msg, data) VALUES ('" + msgname + "','" + mdata + "');";
                    //this._logdebug("Execute SQL: " + str)
                    this._db.executeSQL(this._insertrowsql, msgname, mdata);
                    //this._db.executeSQL(str);
                    sent = true;
                } else {
                    this._logdebug(
                        "No dbcaching enabled.",
                        this._db,
                        this._dbcaching
                    );
                }
            } catch (err) {
                console.error(<string>err);
            }

            //try to send cached message
            this._send_cached();
        } else {
            //if (this._isdebug) console.debug('Sent message direct: msgname=' + msgname);
            sent = this._sendmsg(msgname, mdata);
        }

        return sent;
    }

    /**
     * Reset the cache database and remove all external callbacks and message types
     *
     *
     *
     */
    reset(): void {
        this._messageList = [];
        if (this._db && this._db.reset()) {
            this._logdebug("DB reseted");
            this._db.executeSQL(this._createtablesql);
        } else if (this._db) {
            this._logdebug("try to remove the table");
            this._db.executeSQL(this._droptablesql);
            this._db.executeSQL(this._createtablesql);
        }
    }

    /**
     * get message from server and call the registered callbacks
     *
     * @param msgname - message type
     * @param data - message data
     *
     *
     */
    spoolincoming(msgname: string, data: string): void {
        msgname = msgname.toUpperCase();
        //this._logdebug("Type " + msgname + "  Data " + data);

        //Commit for a cached message sent
        if (msgname === this._msgrecieved) {
            this._delete_cached(data);
            //try to send new cached message
            this._send_cached();
        }

        this._messageList.forEach((messageListItem) => {
            this._handleMsg(messageListItem, msgname, data);
        });
    }

    /*dumpstate():void{

    }*/

    /**
     * Initialize the DB table
     *
     * @remarks - use this function with the sqlite initialize promise
     * to make sure that the database object is created before initialize it
     *
     * @param db - Sqlite database object
     * @example
     * window.sqlite = new PCSqlite(config,"pagecamel.sqlite",true);
     * window.pcws = new PCWebsocket(true,true);
     * window.sqlite.initialize.then(()=>{
     *   window.pcws.initializeSQL(window.sqlite)
     *   onLoadExt();
     * }).catch((msg:string)=>{console.error("Error at SQL initialisation: " + msg)});
     *
     * @returns TRUE if db-caching is enabled
     *
     */
    initializeSQL(db: PCSqlite): boolean {
        this._logdebug("**** initalizeSQL ****");
        this._logdebug("DBType: " + typeof db);
        if (typeof db === "object") {
            this._db = db;

            this._logdebug("Execute SQL: " + this._createtablesql);
            try {
                this._db.executeSQL(this._createtablesql);
                //enable dbcaching
                if (this._iscaching) this._dbcaching = true;
            } catch (err) {
                console.error("initializeSQL error: " + err);
                //disable dbcaching
                this._dbcaching = false;
            }
        } else {
            //disable dbcaching
            this._dbcaching = false;
        }
        return this._dbcaching;
    }

    set isconnected(val: boolean) {
        if (typeof val == "boolean") {
            this._isconnected = val;
            //handle "ISCONNECTED" callback
            this.onConnectionChanged(this._isconnected);
            this._messageList.forEach((messageListItem) => {
                this._handleMsg(
                    messageListItem,
                    this._msgisconnected,
                    this._isconnected ? "1" : "0"
                );
            });
        } else {
            console.error("CallbackType.isconnected needs a boolean value");
        }
    }

    get isconnected(): boolean {
        return this._isconnected;
    }
    /**
     * Overwritable function to handle the connection state change
     * @param isconnected - TRUE if connected
     */
    public onConnectionChanged(isconnected: boolean): void {
        
    }

    private _timerfunc(): void {
        //this._logdebug("Execute timer function...");
        this._send_cached();
    }

    private _sendmsg(msgname: string, data: string, id: string = ""): boolean {
        let sent = false;
        if (this._isconnected) {
            /*
            this._logdebug(
                "Send message: msgname=" +
                    msgname +
                    " data=" +
                    data +
                    " id=" +
                    id
            );
            */
            if (id === "") {
                if (wstransmit(msgname, data)) sent = true;
            } else {
                if (wstransmit(msgname, data, id)) sent = true;
            }
        }
        return sent;
    }

    private _send_cached(): void {
        //this._logdebug("Try to send cached messages...");

        /*if (this._cached_msgs.length > 0) {
            let cached_msg = this._cached_msgs[0];
            this._sendmsg(cached_msg.msg,cached_msg.data,cached_msg.id);
        }
        else {
            this._last_cached_id = 0;
        }*/
        try {
            if (this._db && this._dbcaching) {
                //Check if delta time is expired
                if (
                    Date.now() - this._last_cache_sent >=
                    this._cache_delta_time
                ) {
                    let row = this._db.executeSQL(this._getrowsql);
                    if (row && row.length == 1) {
                        console.log(row);
                        //this._sendmsg(<string>row[0]["msg"],<string>row[0]["data"],<string>row[0]["rowid"]);
                        this._sendmsg(
                            <string>row[0]["msg"],
                            <string>row[0]["data"],
                            <string>row[0]["dbid"]
                        );
                        this._last_cache_sent = Date.now();
                    }
                }
            }
        } catch (err) {
            console.error(err);
        }
    }

    private _delete_cached(msgid: string): void {
        //if  (this._isdebug) console.debug("Try to delete message from cache: msgid=" + msgid);
        this._logdebug("Try to delete message from cache: msgid=" + msgid);
        /*for (let i=0; i<this._cached_msgs.length; i++) {
            if (this._cached_msgs[i].id === msgid) {
                //remove this item and return
                if  (this._isdebug) console.debug("Delete message from cache: msgid=" + msgid);
                this._cached_msgs.splice(i,1);
                return;
            }
        }*/
        try {
            if (this._db && this._dbcaching) {
                this._db.executeSQL(this._deleterowsql, msgid);
                //if dbcache is empty send an OUTBOXEMPTY message
                let num = this._db.executeSQL(this._countcacheditemssql);
                this._logdebug("Number of cached items: ", num![0].num);
                if (num![0].num == 0) {
                    this.send(this._msgoutboxempty, "", false);
                }
                //Reset last cache sent time -> next cache could be send immediately
                this._last_cache_sent = 0;
            }
        } catch (err) {
            console.error(err);
        }
    }

    private _handleMsg(
        messageListItem: CallbackList,
        msgname: string,
        data: string
    ): void {
        //if  (this._isdebug) console.debug("_handleMsg: Check message " + msgname + " with messageListItem: " + messageListItem.messagename);
        /*
        this._logdebug(
            "_handleMsg: Check message " +
                msgname +
                " with messageListItem: " +
                messageListItem.messagename
        );
        */
        if (msgname === messageListItem.messagename) {
            //call the registered callbackfunction
            this._logdebug(
                "Call callback " + messageListItem.callbacks.toString()
            );
            messageListItem.callbacks.forEach((cbfunction) => {
                cbfunction(msgname, data);
            });
        }
    }

    private _logdebug(...args: any[]): void {
        if (!this._isdebug) {
            return;
        }
        args.forEach((val) => {
            console.debug(val);
        });
    }
}
