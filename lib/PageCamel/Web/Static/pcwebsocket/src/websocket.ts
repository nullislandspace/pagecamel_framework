import { PCSqlite } from "./sqlite.js";


interface CallbackType { (messagename: string, data:string): void }

declare function wstransmit(msgname:string,data:string,msgid?:string):any;

interface CallbackList { messagename:string, callbacks:CallbackType[] } 

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
export class PCWebsocket{

    //is the server connection established
    private _isconnected;
    private _isdebug;
    private _iscaching;

    //holds the callback messages and functions
    private _messageList:CallbackList[] = [] ; 

    //timer delta time in seconds
    private _deltatime;

    private _cached_msgs:{msg:string,data:string,id:string}[];
    private _last_cached_id:number;
    private _timer:number;

    //database object
    private _db:PCSqlite|null;
    private _dbtable:string;
    private _dbcaching:boolean;

  
    constructor(caching=false,debug=false){
        this._iscaching=caching;
        this._isdebug=debug;
        this._isconnected=false;
        this._db=null;
        this._dbtable="wstransmit_" + Date.now().toString(); 
        this._dbtable="wstransmit"; 
        this._messageList = [];
        this._deltatime=1000; //milliseconds
        this._cached_msgs = [];
        this._last_cached_id = 0;
        this._dbcaching = false;
        //start timer
        //this._timer=setInterval(()=>this._timerfunc,this._deltatime);
        //this._timer=window.setInterval(()=>{this._timerfunc()},this._deltatime);
        this._timer = 0;
    } 

    /**
     * Register the callbacks to a messagename
     *
     * @param msgname - messagename to register the callbacks
     * @parma callback - Callback-Functions  
     *
     * 
    */
    register(msgname:string, callback:CallbackType[]):void{
        msgname=msgname.toUpperCase();
        let msgexist = false;
        if (this._messageList.length == 0){
            
            if (this._isdebug) callback.forEach(function (fct) {console.debug("Register " + fct.name + " to messagename " + msgname)});
            this._messageList.push({messagename:msgname,callbacks:callback});
            


        } 
        else{
            
            
            for (let i=0; i<this._messageList.length; i++){
                //first check if msgname exists
                if (this._messageList[i].messagename === msgname ){
                    msgexist = true;
                    //then check if callback function exists at msgname
                    for (let j=0; j<callback.length; j++){
                        if (this._messageList[i].callbacks.includes(callback[j])){
                            console.info("Callback " + callback[j].name + " already registered");
                        } 
                        else {
                            if (this._isdebug) console.debug("Register " + callback[j].name + " to messagename " + msgname);
                            this._messageList[i].callbacks.push(callback[j] ); 
                        } 
                    } 
                    
                } 
            }
            //add callback to new msgname if msgname doesn't exist 
            if (!msgexist) {
                if (this._isdebug) callback.forEach(function (fct) {console.debug("Register " + fct.name + " to messagename " + msgname)});
                this._messageList.push({messagename:msgname,callbacks:callback});
            }
        } 
        if (msgname === "ISCONNECTED" && !msgexist) {
            //call the callbackfunction for ISCONNECTED at register to get the first isconnected status
            this._handleMsg({messagename:msgname, callbacks:callback}, msgname, this._isconnected?'1':'0');
        }
    } 

    /**
     * Deregister the callbacks from a messagename
     *
     * @param name - messagename
     * @param callback - Callback-Functions
     * 
    */
    deregister(msgname:string, callback:CallbackType[]):void{
        msgname=msgname.toUpperCase();
        if (this._messageList.length === 0){
            console.log("No callback in the callbacklist");

        } 
        else{
            let msgexist = false;
            for (let i=0; i<this._messageList.length; i++){
                //first check if msgname exists
                if (this._messageList[i].messagename === msgname ){
                    msgexist = true;
                    //search remove the callbacks
                    let cindex = 0;
                    for (let c=0; c<callback.length; c++) {
                        cindex = this._messageList[i].callbacks.indexOf(callback[c]);
                        if (cindex>-1) {
                            if (this._isdebug) console.debug ("Deregister callback=" + callback + " on messagename=" + msgname);
                            this._messageList[i].callbacks.splice(cindex,1);
                        }
                    }
                    //check if messagename has any callbacks
                    if (this._messageList[i].callbacks.length===0){
                        //remove messagename from messagelist if no callbacks exist
                        this._messageList.splice(i,1);
                    }
                }
            }
            if (!msgexist && this._isdebug) {
                console.debug("No deregister: the messagename: " + msgname + " does not exist");
            }
        } 
    } 

    send (msgname:string, mdata:string, caching=false):boolean{
        msgname=msgname.toUpperCase();
        let sent=false;
        if (this._iscaching && caching) {
            //increment last cached id
            //++this._last_cached_id;
            //cache the message
            if (this._isdebug) console.debug('Add message to cache: msgname=' + msgname);
            //this._cached_msgs.push({msg:msgname,data:mdata,id:this._last_cached_id.toString()});
            let sqlstring = "INSERT INTO " + this._dbtable + "(msg, data) VALUES (?, ?);"
            try {
                if (this._db && this._dbcaching) {
                
                    this._db.executeSQL(sqlstring, [msgname, mdata]);
                    sent = true;
                }
            }
            catch (err) {
                console.error(<string>err);
            }
            
            
            //try to send cached message
            this._send_cached();
        }
        else {
            //if (this._isdebug) console.debug('Sent message direct: msgname=' + msgname);
            sent = this._sendmsg(msgname,mdata);
        }
        
        return sent;
    } 

    /**
     * get message from server and call the registered callbacks
     *
     * @param msgname - message type
     * @param data - message data
     *
     * 
    */  
    spoolincoming(msgname:string, data:string):void{
        msgname=msgname.toUpperCase();
        if (this._isdebug) console.debug("Type " + msgname + "  Data " + data);
        

        //Commit for a cached message sent
        if (msgname === "RECIEVED") {
            this._delete_cached(data);
            //try to send new cached message
            this._send_cached();
        }

        this._messageList.forEach((messageListItem) => {this._handleMsg(messageListItem, msgname, data)});

    } 

    dumpstate():void{

    } 

    initializeSQL(db:PCSqlite):boolean {
        if (this._isdebug) console.debug("**** initalizeSQL ****");
        if (this._isdebug) console.debug("DBType: " + typeof(db));
        if (typeof(db) === "object") {
            this._db = db;
            let sqlstring:string = "CREATE TABLE IF NOT EXISTS " + this._dbtable + " (msg TEXT, data TEXT);";
            if (this._isdebug) console.debug("Execute SQL: " + sqlstring);
            try {
                this._db.executeSQL(sqlstring);
                //enable dbcaching
                if (this._iscaching) this._dbcaching = true;
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

    set isconnected(val:boolean){
        if (typeof(val)=="boolean"){
            this._isconnected=val;
            //handle "ISCONNECTED" callback
            this._messageList.forEach((messageListItem) => {this._handleMsg(messageListItem, "ISCONNECTED", this._isconnected?'1':'0')});
        } 
        else{
            console.error("CallbackType.isconnected needs a boolean value");
        } 
        
    } 

    private _timerfunc():void{
        console.log("Execute timer function...");
        this._send_cached();
        

    } 

    private _sendmsg(msgname:string, data:string, id:string=''):boolean{
        let sent = false;
        if (this._isconnected) {
            if (this._isdebug)  console.debug("Send message: msgname=" + msgname + " data=" + data + " id=" + id);
            if (id === '') {
                if (wstransmit(msgname, data)) sent = true;
                
            }
            else {
                if (wstransmit(msgname, data, id)) sent = true;
            }
        }
        return sent;

    } 



    private _send_cached():void {
        if (this._isdebug) console.debug("Try to send cached messages...");
        /*if (this._cached_msgs.length > 0) {
            let cached_msg = this._cached_msgs[0];
            this._sendmsg(cached_msg.msg,cached_msg.data,cached_msg.id);
        }
        else {
            this._last_cached_id = 0;
        }*/
        let sqlstring = "SELECT rowid, msg, data FROM " + this._dbtable + " ORDER BY rowid LIMIT 1;";
        try {
            if (this._db && this._dbcaching) {
                let row = this._db.executeSQL(sqlstring);
                if (row && row.length == 1) {
                    this._sendmsg(row[1].toString(),row[2].toString(),row[0].toString());
                }
                
            }
        }
        catch (err) {
            console.error(err);
        }
    
    }

    private _delete_cached(msgid:string):void {
        if  (this._isdebug) console.debug("Try to delete message from cache: msgid=" + msgid);
        /*for (let i=0; i<this._cached_msgs.length; i++) {
            if (this._cached_msgs[i].id === msgid) {
                //remove this item and return
                if  (this._isdebug) console.debug("Delete message from cache: msgid=" + msgid);
                this._cached_msgs.splice(i,1);
                return;
            }
        }*/
        let sqlstring = "DELETE FROM " + this._dbtable + " WHERE rowid=?;"
        try {
            if (this._db && this._dbcaching) {
                this._db.executeSQL(sqlstring,[msgid]);
                
            }
        }
        catch (err) {
            console.error(err);
        }
        
    }

    private _handleMsg(messageListItem:CallbackList, msgname:string, data:string):void {
        if  (this._isdebug) console.debug("_handleMsg: Check message " + msgname + " with messageListItem: " + messageListItem.messagename);
        if (msgname === messageListItem.messagename) {
            //call the registered callbackfunction
            if  (this._isdebug) console.debug("Call callback " + messageListItem.callbacks.toString());
            messageListItem.callbacks.forEach((cbfunction) => {cbfunction(msgname, data)});
        }
    }

    
    


} 
