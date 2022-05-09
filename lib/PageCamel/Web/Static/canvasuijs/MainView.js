class MainView extends UIView {
    constructor(canvas, messagetype) {
        super(canvas);
        this.messagetype = messagetype;
        self = this;
    }
    createElements() {
        executeSQL(`CREATE TABLE IF NOT EXISTS tableplan(id TEXT PRIMARY KEY,\
        data TEXT, timestamp INTEGER
        );`);
        self.addElement('TablePlan', {
            name: self.messagetype, active: true,
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 20, y: 20, width: 1360, height: 860, sendTablePlan: self.sendData,
        });
        
        console.log('ELEMENT:',self.element(self.messagetype).getList());
    }
    load() {
        executeSQL(`CREATE TABLE IF NOT EXISTS tableplan(id TEXT PRIMARY KEY,\
            data TEXT, timestamp INTEGER
            );`);
        sendMessage({
            type: 'GET' + self.messagetype.toUpperCase()
        });
    }
    gotMessage(msg) {
        if (msg.type == self.messagetype.toUpperCase()) {
            console.log("Got new" + self.messagetype + "from server");
            console.log(msg.data)
            self.element(self.messagetype).setList(msg.data[0], msg.data[1]);
        }
    }
    sendData() {
        if (!wsconnected) {
            console.log("Can't send tableplan to server (not connected)");
            return;
        }
        var tableplan = self.element(self.messagetype).getList();
        if (typeof tableplan === 'undefined' || typeof tableplan[0] === 'undefined') {
            return;
        }
        sendMessage({
            type: 'SET' + self.messagetype.toUpperCase(),
            data: tableplan
        });
    }
}