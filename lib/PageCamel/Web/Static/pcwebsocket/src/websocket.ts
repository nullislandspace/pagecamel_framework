export interface CallbackType { (messagename: string, data:string): void }

interface CallbackList { messagename:string, callbacks:CallbackType[] } 

  /**
     * Websocket connection class           
     * @remarks
     *
     * Use this class to communicate over a websocket. 
     *
     * * Register some callback-functions for special messagenames.
     *
     * * Use send() to send data to the server
     *
     *
     */
export class PCWebsocket{

    //is the server connection established
    private _isconnected;
    private _isdebug;
    private _iscaching;

    //holds the callback messages and functions
    private _messageList:CallbackList[]  ; 

    //timer delta time in seconds
    private _deltatime;

  
    constructor(caching=false,debug=false){
        this._iscaching=caching;
        this._isdebug=debug;
        this._isconnected=false;
        this._messageList=[];
        this._deltatime=1;
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

        if (this._messageList.length == 0){
            
            if (this._isdebug) callback.forEach(function (fct) {console.debug("Register " + fct.name + " to messagename " + msgname)});
            this._messageList.push({messagename:msgname,callbacks:callback});


        } 
        else{
            for (let i=0; i<this._messageList.length; i++){
                if (this._messageList[i].messagename == msgname ){
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
        } 
    } 

    /**
     * Deregister the callbacks from a messagename
     *
     * @param name - messagename
     * @param callback - Callback-Functions
     * 
    */
    deregister(name:string, callback:CallbackType[]):void{
        if (this._messageList.length == 0){
            console.log("No callback in the callbacklist");

        } 
        else{
        } 
    } 

    send (cbname:string, data:string, caching=false):boolean{

        return false;
    } 

    spoolincoming(cbname:string, data:string):void{

    } 

    dumpstate():void{

    } 

    set isconnected(val:boolean){
        if (typeof(val)=="boolean"){
            this._isconnected=val;
        } 
        else{
            console.error("CallbackType.isconnected needs a boolean value");
        } 
        
    } 

    private _timer():void{

    } 

    private _send():void{
        wstransmit('name', 'data', 'ID:0815');

    } 

} 
