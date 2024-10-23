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
    /**
     * Constructor for class
     * @param caching - enable database caching
     * @param debug - use console debuging
     *
     */
    constructor(caching = false, debug = false) {
        //holds the callback messages and functions
        this._messageList = [];
        //timer delta time in seconds
        this._deltatime = 250;
        //Cache send delta time in ms
        this._cache_delta_time = 5000;
        //internal operation messages
        this._msgoutboxempty = "OUTBOXEMPTY";
        this._msgrecieved = "RECIEVED";
        this._msgisconnected = "ISCONNECTED";
        this._msgqueue = [];
        this._msgqueueexcept = [];
        this._msgqueueenabled = false;
        this._iscaching = caching;
        this._isdebug = debug;
        this._isconnected = false;
        //db init
        this._db = null;
        this._dbtable = "wstransmit_" + Date.now().toString();
        this._dbtable = "wsoutbox";
        this._createtablesql =
            "CREATE TABLE IF NOT EXISTS " +
                this._dbtable +
                " (dbid INT, msg TEXT, data TEXT);";
        this._droptablesql = "DROP TABLE " + this._dbtable + ";";
        this._getrowsql =
            "SELECT dbid, msg, data FROM " +
                this._dbtable +
                " ORDER BY dbid LIMIT 1;";
        this._deleterowsql =
            "DELETE FROM " +
                this._dbtable +
                " WHERE dbid = ?;";
        this._insertrowsql =
            "INSERT INTO " +
                this._dbtable +
                "(dbid, msg, data) VALUES (?, ?, ?);";
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
    register(msgname, modulename, callback) {
        msgname = msgname.toUpperCase();
        let msgexist = false;
        if (this._messageList.length == 0) {
            if (this._isdebug)
                callback.forEach(function (fct) {
                    console.debug("Register " + fct.name + " to messagename " + msgname);
                });
            this._messageList.push({
                messagename: msgname,
                callbacks: callback,
            });
        }
        else {
            for (let i = 0; i < this._messageList.length; i++) {
                //first check if msgname exists
                if (this._messageList[i].messagename === msgname && this._messageList[i].modulename === modulename) {
                    //console.log("Replacing callbacks for module " + modulename + " message " + msgname);
                    this._messageList[i].callbacks = callback;
                    msgexist = true;
                }
            }
            //add callback to new msgname if msgname doesn't exist
            if (!msgexist) {
                //console.log("Registering callbacks for module " + modulename + " message " + msgname);
                this._messageList.push({
                    messagename: msgname,
                    modulename: modulename,
                    callbacks: callback,
                });
            }
        }
        if (msgname === this._msgisconnected && !msgexist) {
            //call the callbackfunction for ISCONNECTED at register to get the first isconnected status
            this._handleMsg({ messagename: msgname, callbacks: callback }, msgname, this._isconnected ? "1" : "0");
        }
    }
    /**
     * Deregister the callbacks from a messagename
     *
     * @param name - messagename
     * @param callback - Callback-Functions
     *
     */
    deregister(msgname, callback) {
        msgname = msgname.toUpperCase();
        if (this._messageList.length === 0) {
            console.log("No callback in the callbacklist");
        }
        else {
            let msgexist = false;
            for (let i = 0; i < this._messageList.length; i++) {
                //first check if msgname exists
                if (this._messageList[i].messagename === msgname) {
                    msgexist = true;
                    //search remove the callbacks
                    let cindex = 0;
                    for (let c = 0; c < callback.length; c++) {
                        cindex = this._messageList[i].callbacks.indexOf(callback[c]);
                        if (cindex > -1) {
                            this._logdebug("Deregister callback=" +
                                callback +
                                " on messagename=" +
                                msgname);
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
                this._logdebug("No deregister: the messagename: " +
                    msgname +
                    " does not exist");
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
    send(msgname, mdata, caching = false) {
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
                    var timestamp = new Date().getTime();
                    var randidx = Math.floor(Math.random() * 10000);
                    var dbid = ((timestamp * 10000) + randidx).toString();
                    this._db.executeSQL(this._insertrowsql, dbid, msgname, mdata);
                    //this._db.executeSQL(str);
                    sent = true;
                }
                else {
                    this._logdebug("No dbcaching enabled.", this._db, this._dbcaching);
                }
            }
            catch (err) {
                console.error(err);
            }
            //try to send cached message
            this._send_cached();
        }
        else {
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
    reset() {
        this._messageList = [];
        if (this._db && this._db.reset()) {
            this._logdebug("DB reseted");
            this._db.executeSQL(this._createtablesql);
        }
        else if (this._db) {
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
    spoolincoming(msgname, data) {
        msgname = msgname.toUpperCase();
        //this._logdebug("Type " + msgname + "  Data " + data);
        //console.log("Type " + msgname + "  Data " + data);
        //Commit for a cached message sent
        if (msgname === this._msgrecieved) {
            this._delete_cached(data);
            //try to send new cached message
            this._send_cached();
        }
        //console.log(this._messageList);
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
    initializeSQL(db) {
        this._logdebug("**** initalizeSQL ****");
        this._logdebug("DBType: " + typeof db);
        if (typeof db === "object") {
            this._db = db;
            this._logdebug("Execute SQL: " + this._createtablesql);
            try {
                this._db.executeSQL(this._createtablesql);
                //enable dbcaching
                if (this._iscaching)
                    this._dbcaching = true;
            }
            catch (err) {
                console.error("initializeSQL error: " + err);
                //disable dbcaching
                this._dbcaching = false;
            }
        }
        else {
            //disable dbcaching
            this._dbcaching = false;
        }
        return this._dbcaching;
    }
    set isconnected(val) {
        if (typeof val == "boolean") {
            this._isconnected = val;
            //handle "ISCONNECTED" callback
            this.onConnectionChanged(this._isconnected);
            this._messageList.forEach((messageListItem) => {
                this._handleMsg(messageListItem, this._msgisconnected, this._isconnected ? "1" : "0");
            });
        }
        else {
            console.error("CallbackType.isconnected needs a boolean value");
        }
    }
    get isconnected() {
        return this._isconnected;
    }
    checkOutboxEmpty() {
        if (this._db) {
            let num = this._db.executeSQL(this._countcacheditemssql);
            this._logdebug("Number of cached items: ", num[0].num);
            if (num[0].num == 0) {
                return true;
            }
        }
        return false;
    }
    isAllSaved() {
        if (this._db && this._db.isAllSaved()) {
            return true;
        }
        return false;
    }
    /**
     * Overwritable function to handle the connection state change
     * @param isconnected - TRUE if connected
     */
    onConnectionChanged(isconnected) { }
    _timerfunc() {
        //this._logdebug("Execute timer function...");
        this._send_cached();
    }
    _sendmsg(msgname, data, id = "") {
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
                if (wstransmit(msgname, data))
                    sent = true;
            }
            else {
                if (wstransmit(msgname, data, id))
                    sent = true;
            }
        }
        return sent;
    }
    _send_cached() {
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
                if (Date.now() - this._last_cache_sent >=
                    this._cache_delta_time) {
                    let row = this._db.executeSQL(this._getrowsql);
                    if (row && row.length == 1) {
                        //console.log(row);
                        //this._sendmsg(<string>row[0]["msg"],<string>row[0]["data"],<string>row[0]["rowid"]);
                        this._sendmsg(row[0]["msg"], row[0]["data"], row[0]["dbid"]);
                        this._last_cache_sent = Date.now();
                    }
                }
            }
        }
        catch (err) {
            console.error(err);
        }
    }
    _delete_cached(msgid) {
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
                this._logdebug("Number of cached items: ", num[0].num);
                if (num[0].num == 0) {
                    this.send(this._msgoutboxempty, "", false);
                }
                //Reset last cache sent time -> next cache could be send immediately
                this._last_cache_sent = 0;
            }
        }
        catch (err) {
            console.error(err);
        }
    }
    _handleMsg(messageListItem, msgname, data) {
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
            if ((this._msgqueueenabled &&
                this._msgqueueexcept.includes(msgname)) ||
                !this._msgqueueenabled) {
                //call the registered callbackfunction
                this._logdebug("Call callback " + messageListItem.callbacks.toString());
                messageListItem.callbacks.forEach((cbfunction) => {
                    cbfunction(msgname, data);
                });
            }
            else {
                //add message to queue
                this._msgqueue.push({ msgname: msgname, data: data });
            }
        }
    }
    _logdebug(...args) {
        if (!this._isdebug) {
            return;
        }
        args.forEach((val) => {
            //console.debug(val);
        });
    }
    /**
     * Enable the message queue with all incoming messages
     * @param whitelistedMessages - Array of message names which should not be queued, they will be handled immediately
     */
    startMessageQueueing(whitelistedMessages) {
        this._msgqueueexcept = whitelistedMessages;
        this._msgqueueenabled = true;
    }
    /**
     * Stop adding messages to the queue and start working off the queue
     */
    stopMessageQueueing() {
        this._msgqueueenabled = false;
        this._msgqueue.forEach((msg) => {
            this._messageList.forEach((messageListItem) => {
                this._handleMsg(messageListItem, msg.msgname, msg.data);
            });
        });
        this._msgqueue = [];
    }
}
