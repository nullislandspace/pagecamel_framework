export interface CallbackType { (cbname: string, data:string): void }

interface CallbackList { cbname:string, callbacks:CallbackType[] } 


export class CXWebsocket{

    //is the server connection established
    private _isconnected=false;

    //holds the callback messages and functions
    private _messageList:CallbackList[] =[] ; 

    //timer delta time in seconds
    private _deltatime=1;

    register(name:string, callback:CallbackType[]):void{
        if (this._messageList.length == 0){
            this._messageList.push({cbname:name,callbacks:callback});

        } 
        else{
            for (let i=0; i<this._messageList.length; i++){
                if (this._messageList[i].cbname == name ){
                    for (let j=0; j<callback.length; j++){
                        if (this._messageList[i].callbacks.includes(callback[j])){
                            console.log("Callback allready registered");
                        } 
                        else {
                            this._messageList[i].callbacks.push(callback[j] ); 
                        } 
                    } 
                    
                } 
            } 
        } 
    } 

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

    } 

} 