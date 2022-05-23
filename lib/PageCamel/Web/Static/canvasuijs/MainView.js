class MainView extends UIView {
    constructor(canvas, messagetype) {
        super(canvas);
        this.messagetype = messagetype;
        this.invoices = [];
        this.views;
        this.selectedTable;
    }
    createElements = () => {
        this.addElement('TablePlan', {
            name: this.messagetype,
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 20, y: 20, width: 1360, height: 860, sendTablePlan: this.sendData, callback: (number) => {
                this.setActive(false);
                this.selectedTable = number;
                this.views.paymentview.billTable(number, this.invoices);
                triggerRepaint();
            }
        });
        for (var invoice of this.invoices) {
            var table = invoice.table;
            if (invoice.articles.length > 0) {
                this.element(this.messagetype).setTableActive(table, true);
            }
        }
    }
    setTableView = (table_active) => {
        this.setActive(true);
        this.element(this.messagetype).setTableActive(this.selectedTable, table_active);
    }
    load = (views) => {
        this.views = views;
        executeSQL(`CREATE TABLE IF NOT EXISTS tableplan(id TEXT PRIMARY KEY,\
            data TEXT, timestamp INTEGER
            );`);
        executeSQL(`CREATE TABLE IF NOT EXISTS invoices(id TEXT PRIMARY KEY AUTOINCREMENT,\
                data TEXT
                );`);
        
        var invoices = executeSQL("SELECT data FROM invoices;");
        if (invoices[0] !== undefined) {
            this.invoices = JSON.parse(invoices[0].data);
        }

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