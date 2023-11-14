"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PCWebsocket = void 0;
class PCWebsocket {
    _isconnected;
    _isdebug;
    _iscaching;
    _messageList = [];
    _deltatime = 250;
    _cached_msgs;
    _last_cached_id;
    _timer;
    _last_cache_sent;
    _cache_delta_time = 5000;
    _db;
    _dbtable;
    _dbcaching;
    _createtablesql;
    _getrowsql;
    _deleterowsql;
    _insertrowsql;
    _countcacheditemssql;
    _droptablesql;
    _msgoutboxempty = "OUTBOXEMPTY";
    _msgrecieved = "RECIEVED";
    _msgisconnected = "ISCONNECTED";
    _msgqueue = [];
    _msgqueueexcept = [];
    _msgqueueenabled = false;
    constructor(caching = false, debug = false) {
        this._iscaching = caching;
        this._isdebug = debug;
        this._isconnected = false;
        this._db = null;
        this._dbtable = "wstransmit_" + Date.now().toString();
        this._dbtable = "wstransmit";
        this._createtablesql =
            "CREATE TABLE IF NOT EXISTS " +
                this._dbtable +
                " (time INT, msg TEXT, data TEXT);";
        this._droptablesql = "DROP TABLE " + this._dbtable + ";";
        this._getrowsql =
            "SELECT CAST(rowid as text) || '_' || CAST(time as text) AS dbid, msg, data FROM " +
                this._dbtable +
                " ORDER BY time,rowid LIMIT 1;";
        this._deleterowsql =
            "DELETE FROM " +
                this._dbtable +
                " WHERE CAST(rowid as text) || '_' || CAST(time as text) = ?;";
        this._insertrowsql =
            "INSERT INTO " +
                this._dbtable +
                "(time, msg, data) VALUES ((strftime('%s','now') || substr(strftime('%f','now'),4)),?, ?);";
        this._countcacheditemssql =
            "SELECT count(*) as num FROM " + this._dbtable + ";";
        this._messageList = [];
        this._cached_msgs = [];
        this._last_cached_id = 0;
        this._last_cache_sent = 0;
        this._dbcaching = false;
        this._timer = window.setInterval(() => {
            this._timerfunc();
        }, this._deltatime);
    }
    register(msgname, callback) {
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
                if (this._messageList[i].messagename === msgname) {
                    msgexist = true;
                    for (let j = 0; j < callback.length; j++) {
                        if (this._messageList[i].callbacks.includes(callback[j])) {
                            console.info("Callback " +
                                callback[j].name +
                                " already registered");
                        }
                        else {
                            this._logdebug("Register " +
                                callback[j].name +
                                " to messagename " +
                                msgname);
                            this._messageList[i].callbacks.push(callback[j]);
                        }
                    }
                }
            }
            if (!msgexist) {
                if (this._isdebug)
                    callback.forEach(function (fct) {
                        console.debug("Register " +
                            fct.name +
                            " to messagename " +
                            msgname);
                    });
                this._messageList.push({
                    messagename: msgname,
                    callbacks: callback,
                });
            }
        }
        if (msgname === this._msgisconnected && !msgexist) {
            this._handleMsg({ messagename: msgname, callbacks: callback }, msgname, this._isconnected ? "1" : "0");
        }
    }
    deregister(msgname, callback) {
        msgname = msgname.toUpperCase();
        if (this._messageList.length === 0) {
            console.log("No callback in the callbacklist");
        }
        else {
            let msgexist = false;
            for (let i = 0; i < this._messageList.length; i++) {
                if (this._messageList[i].messagename === msgname) {
                    msgexist = true;
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
                    if (this._messageList[i].callbacks.length === 0) {
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
    send(msgname, mdata, caching = false) {
        msgname = msgname.toUpperCase();
        let sent = false;
        if (this._iscaching && caching) {
            this._logdebug("Add message to cache: msgname=" + msgname);
            try {
                if (this._db && this._dbcaching) {
                    this._db.executeSQL(this._insertrowsql, msgname, mdata);
                    sent = true;
                }
                else {
                    this._logdebug("No dbcaching enabled.", this._db, this._dbcaching);
                }
            }
            catch (err) {
                console.error(err);
            }
            this._send_cached();
        }
        else {
            sent = this._sendmsg(msgname, mdata);
        }
        return sent;
    }
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
    spoolincoming(msgname, data) {
        msgname = msgname.toUpperCase();
        if (msgname === this._msgrecieved) {
            this._delete_cached(data);
            this._send_cached();
        }
        this._messageList.forEach((messageListItem) => {
            this._handleMsg(messageListItem, msgname, data);
        });
    }
    initializeSQL(db) {
        this._logdebug("**** initalizeSQL ****");
        this._logdebug("DBType: " + typeof db);
        if (typeof db === "object") {
            this._db = db;
            this._logdebug("Execute SQL: " + this._createtablesql);
            try {
                this._db.executeSQL(this._createtablesql);
                if (this._iscaching)
                    this._dbcaching = true;
            }
            catch (err) {
                console.error("initializeSQL error: " + err);
                this._dbcaching = false;
            }
        }
        else {
            this._dbcaching = false;
        }
        return this._dbcaching;
    }
    set isconnected(val) {
        if (typeof val == "boolean") {
            this._isconnected = val;
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
    onConnectionChanged(isconnected) { }
    _timerfunc() {
        this._send_cached();
    }
    _sendmsg(msgname, data, id = "") {
        let sent = false;
        if (this._isconnected) {
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
        try {
            if (this._db && this._dbcaching) {
                if (Date.now() - this._last_cache_sent >=
                    this._cache_delta_time) {
                    let row = this._db.executeSQL(this._getrowsql);
                    if (row && row.length == 1) {
                        console.log(row);
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
        this._logdebug("Try to delete message from cache: msgid=" + msgid);
        try {
            if (this._db && this._dbcaching) {
                this._db.executeSQL(this._deleterowsql, msgid);
                let num = this._db.executeSQL(this._countcacheditemssql);
                this._logdebug("Number of cached items: ", num[0].num);
                if (num[0].num == 0) {
                    this.send(this._msgoutboxempty, "", false);
                }
                this._last_cache_sent = 0;
            }
        }
        catch (err) {
            console.error(err);
        }
    }
    _handleMsg(messageListItem, msgname, data) {
        if (msgname === messageListItem.messagename) {
            if ((this._msgqueueenabled &&
                this._msgqueueexcept.includes(msgname)) ||
                !this._msgqueueenabled) {
                this._logdebug("Call callback " + messageListItem.callbacks.toString());
                messageListItem.callbacks.forEach((cbfunction) => {
                    cbfunction(msgname, data);
                });
            }
            else {
                this._msgqueue.push({ msgname: msgname, data: data });
            }
        }
    }
    _logdebug(...args) {
        if (!this._isdebug) {
            return;
        }
        args.forEach((val) => {
            console.debug(val);
        });
    }
    startMessageQueueing(whitelistedMessages) {
        this._msgqueueexcept = whitelistedMessages;
        this._msgqueueenabled = true;
    }
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
exports.PCWebsocket = PCWebsocket;
//# sourceMappingURL=websocket.js.map