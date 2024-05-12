import { PCSqlite } from "./sqlite.js";
interface CallbackType {
    (messagename: string, data: string | object): void;
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
export declare class PCWebsocket {
    private _isconnected;
    private _isdebug;
    private _iscaching;
    private _messageList;
    private _deltatime;
    private _cached_msgs;
    private _last_cached_id;
    private _timer;
    private _last_cache_sent;
    private _cache_delta_time;
    private _db;
    private _dbtable;
    private _dbcaching;
    private _createtablesql;
    private _getrowsql;
    private _deleterowsql;
    private _insertrowsql;
    private _countcacheditemssql;
    private _droptablesql;
    private _msgoutboxempty;
    private _msgrecieved;
    private _msgisconnected;
    private _msgqueue;
    private _msgqueueexcept;
    private _msgqueueenabled;
    /**
     * Constructor for class
     * @param caching - enable database caching
     * @param debug - use console debuging
     *
     */
    constructor(caching?: boolean, debug?: boolean);
    /**
     * Register the callbacks to a messagename
     *
     * @param msgname - messagename to register the callbacks
     * @param callback - Callback-Functions
     *
     *
     */
    register(msgname: string, callback: CallbackType[]): void;
    /**
     * Deregister the callbacks from a messagename
     *
     * @param name - messagename
     * @param callback - Callback-Functions
     *
     */
    deregister(msgname: string, callback: CallbackType[]): void;
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
    send(msgname: string, mdata: string, caching?: boolean): boolean;
    /**
     * Reset the cache database and remove all external callbacks and message types
     *
     *
     *
     */
    reset(): void;
    /**
     * get message from server and call the registered callbacks
     *
     * @param msgname - message type
     * @param data - message data
     *
     *
     */
    spoolincoming(msgname: string, data: string): void;
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
    initializeSQL(db: PCSqlite): boolean;
    set isconnected(val: boolean);
    get isconnected(): boolean;
    checkOutboxEmpty(): boolean;
    isAllSaved(): boolean;
    /**
     * Overwritable function to handle the connection state change
     * @param isconnected - TRUE if connected
     */
    onConnectionChanged(isconnected: boolean): void;
    private _timerfunc;
    private _sendmsg;
    private _send_cached;
    private _delete_cached;
    private _handleMsg;
    private _logdebug;
    /**
     * Enable the message queue with all incoming messages
     * @param whitelistedMessages - Array of message names which should not be queued, they will be handled immediately
     */
    startMessageQueueing(whitelistedMessages: string[]): void;
    /**
     * Stop adding messages to the queue and start working off the queue
     */
    stopMessageQueueing(): void;
}
export {};
//# sourceMappingURL=websocket.d.ts.map