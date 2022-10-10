declare var window: any;


function onTestMessage(msgname:string, data:string):void{
    console.log("Please note onTestMessage data: " + data);
} 

function onTestMessage2(msgname:string, data:string):void{
    console.log("Callback onTestMessage2: "+ data);
} 



function getConnectionStatus(msgname:string, data:string):void {
    console.log("Connection status: " + data);
}


export function onLoadExt () {

    /*
    let dirbutton:HTMLButtonElement = <HTMLButtonElement>document.getElementById("directsend");
    let indirbutton:HTMLButtonElement = <HTMLButtonElement>document.getElementById("indirectsend");
    dirbutton.onclick=onDirectClick;
    indirbutton.onclick=onIndirectClick;
    */
    

    //dirbutton.addEventListener('click', (e:Event) => onDirectClick());

    window.pcws.register("NOTIFICATION",[onTestMessage] );
    window.pcws.register("RECIEVED",[onTestMessage2] );
    window.pcws.register("RECIEVED",[onTestMessage] );
    window.pcws.register("ISCONNECTED", [getConnectionStatus]);

    window.pcws.send("Testmessage","Meine Daten sind ziemlich kurz!");
    window.pcws.send("cachemessage","Meine 1. cached Daten sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine 2. cached Daten sind ziemlich kurz!", true);
    window.pcws.send("cachemessage","Meine 3. cached Daten sind ziemlich kurz!", true);
}

