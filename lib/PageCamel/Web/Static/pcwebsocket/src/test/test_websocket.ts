


function onTestMessage(cbname:string, data:string):void{
    console.log("Please note: " + data);
} 

function onTestMessage2(cbname:string, data:string):void{
    //console.log("Callback " + this.name + " called");
} 


export function onLoadExt () {
    window.pcws.register("NOTIFICATION",[onTestMessage] );
    window.pcws.register("testmessage",[onTestMessage2] );
}
