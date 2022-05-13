class MainView extends UIView{
    constructor(canvas, messagetype) {
        super(canvas);
        this.messagetype = messagetype;
    }
    createElements = (paymentview) => {
        this.addElement('TablePlan', {
            name: this.messagetype,
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 20, y: 20, width: 1360, height: 860, sendTablePlan: this.sendData, callback: (number) => {
                this.setActive(false);
                paymentview.billTable(number);
                console.log(paymentview);
                triggerRepaint();
                
            }
        });
    }
    load = () => {
        executeSQL(`CREATE TABLE IF NOT EXISTS tableplan(id TEXT PRIMARY KEY,\
            data TEXT, timestamp INTEGER
            );`);
        executeSQL(`CREATE TABLE IF NOT EXISTS invoices(id TEXT PRIMARY KEY AUTOINCREMENT,\
                data TEXT
                );`);
        sendMessage({
            type: 'GET' + this.messagetype.toUpperCase()
        });
    }
    gotMessage = (msg) => {
        if (msg.type == this.messagetype.toUpperCase()) {
            console.log("Got new " + this.messagetype + " from server:", msg.data);
            this.element(this.messagetype).setList(msg.data[0], msg.data[1]);
        }
    }
    sendData = () => {
        if (!wsconnected) {
            console.log("Can't send tableplan to server (not connected)");
            return;
        }
        var tableplan = this.element(this.messagetype).getList();
        if (typeof tableplan === 'undefined' || typeof tableplan[0] === 'undefined') {
            return;
        }
        sendMessage({
            type: 'SET' + this.messagetype.toUpperCase(),
            data: tableplan
        });
    }
}