class SplitView extends UIView {
    constructor(canvas) {
        super(canvas);
        this.views;
        this.rebookShowInvoice = [];
        this.rebookArticles = [];
        this.invoiceLeft = { invoice: [] };
        this.invoiceRight = { invoice: [] };
    }
    moveLeft = (id) => {
        this.invoiceLeft = [...this.element('splitLeft').getList()];
        this.invoiceRight = [...this.element('splitRight').getList()];
        if (this.invoiceLeft[this.invoiceLeft.length - 1] !== undefined && this.invoiceRight[this.invoiceRight.length - 1] !== undefined) {
            if (this.invoiceLeft[this.invoiceLeft.length - 1].lineitem[0].displaytext == 'BAR' && this.invoiceRight[this.invoiceRight.length - 1].lineitem[0].displaytext != 'BAR') {
                this.element('splitLeft').setList([]);
                this.invoiceLeft = [];
            }
        }
        if (this.invoiceRight[id] !== undefined && this.invoiceRight[this.invoiceRight.length - 1].lineitem[0].displaytext !== 'BAR') {
            //this.invoiceRight[id].qty
            for (var invoice of this.invoiceLeft) {
                if (invoice.itemID == this.invoiceRight[id].itemID) {
                    invoice.qty += 1;
                    this.invoiceRight[id].qty -= 1;
                    if (this.invoiceRight[id].qty <= 0) {
                        this.invoiceRight.splice(id, 1);
                    }
                    this.element('splitLeft').setList([...this.invoiceLeft]);
                    this.element('splitRight').setList([...this.invoiceRight]);
                    return;
                }
            }
            this.invoiceLeft.push({ ...this.invoiceRight[id] });
            this.invoiceLeft[this.invoiceLeft.length - 1].qty = 1;
            if (this.invoiceRight[id].qty <= 1) {
                this.invoiceRight.splice(id, 1);
            }
            else {
                this.invoiceRight[id].qty -= 1;
            }
            this.element('splitLeft').setList([...this.invoiceLeft]);
            this.element('splitRight').setList([...this.invoiceRight]);
        }
    }
    moveRight = (id) => {
        this.invoiceLeft = [...this.element('splitLeft').getList()];
        this.invoiceRight = [...this.element('splitRight').getList()];
        if (this.invoiceRight[this.invoiceRight.length - 1] !== undefined && this.invoiceLeft[this.invoiceLeft.length - 1] !== undefined) {
            if (this.invoiceRight[this.invoiceRight.length - 1].lineitem[0].displaytext == 'BAR' && this.invoiceLeft[this.invoiceLeft.length - 1].lineitem[0].displaytext != 'BAR') {
                this.element('splitRight').setList([]);
                this.invoiceRight = [];
            }
        }
        if (this.invoiceLeft[id] !== undefined && this.invoiceLeft[this.invoiceLeft.length - 1].lineitem[0].displaytext !== 'BAR') {
            for (var invoice of this.invoiceRight) {
                if (invoice.itemID == this.invoiceLeft[id].itemID) {
                    invoice.qty += 1;
                    this.invoiceLeft[id].qty -= 1;
                    if (this.invoiceLeft[id].qty <= 0) {
                        this.invoiceLeft.splice(id, 1);
                    }
                    this.element('splitLeft').setList([...this.invoiceLeft]);
                    this.element('splitRight').setList([...this.invoiceRight]);
                    return;
                }
            }

            this.invoiceRight.push({ ...this.invoiceLeft[id] });
            this.invoiceRight[this.invoiceRight.length - 1].qty = 1;
            if (this.invoiceLeft[id].qty <= 1) {
                this.invoiceLeft.splice(id, 1);
            }
            else {
                this.invoiceLeft[id].qty -= 1;
            }
            this.element('splitLeft').setList([...this.invoiceLeft]);
            this.element('splitRight').setList([...this.invoiceRight]);
        }
    }
    rebookTable = (paylist) => {
        var invoices = [...this.element(paylist).getList()];
        if (invoices.length > 0) {
            if (invoices[invoices.length - 1].lineitem[0].displaytext !== 'BAR') {
                this.rebookShowInvoice = invoices;
                var articles;
                var articles_index;
                for (var i in this.views.paymentview.invoices) {
                    var invoice = this.views.paymentview.invoices[i];
                    if (invoice.table == this.views.paymentview.selectedTable) {
                        articles = [...invoice.articles];
                        articles_index = i;
                    }
                }
                var rebook_articels = [];
                var paylistRight = [...this.element('splitRight').getList()];
                var paylistLeft = [...this.element('splitLeft').getList()];
                var new_invoice_articles = [];
                if (paylist == 'splitLeft') {
                    for (var i in paylistLeft) {
                        var article = paylistLeft[i];
                        rebook_articels.push({ article: article.article, qty: article.qty, itemID: article.itemID });
                    }
                    for (var i in paylistRight) {
                        var article = paylistRight[i];
                        new_invoice_articles.push({ article: article.article, qty: article.qty, itemID: article.itemID });
                    }
                }
                else if (paylist == 'splitRight') {
                    for (var i in paylistRight) {
                        var article = paylistRight[i];
                        rebook_articels.push({ article: article.article, qty: article.qty, itemID: article.itemID });
                    }
                    for (var i in paylistLeft) {
                        var article = paylistLeft[i];
                        new_invoice_articles.push({ article: article.article, qty: article.qty, itemID: article.itemID });
                    }
                }
                this.views.mainview.element(this.views.mainview.messagetype).setTableActive(this.views.paymentview.selectedTable, true);
                this.views.paymentview.invoices[articles_index].articles = new_invoice_articles;
                this.views.paymentview.setInvoiceSQLDB();
                this.rebookArticles = rebook_articels;
                this.setActive(false);
                this.views.mainview.setTableRebookView(true);
                this.element('splitRight').setList([]);
                this.element('splitLeft').setList([]);
                this.invoiceRight = [];
                this.invoiceLeft = [];
                for (var invoice of this.views.paymentview.invoices) {
                    if (invoice.table == this.views.paymentview.selectedTable && invoice.articles.length > 0) {
                        this.views.mainview.setTableView(true);
                        return;
                    }
                }
                this.views.mainview.setTableView(false);
            }
        }
    }
    createInvoice = (paylist) => {
        var invoices = this.element(paylist).getList();

        if (invoices[invoices.length - 1] !== undefined) {
            if (invoices[invoices.length - 1].lineitem[0].displaytext != 'BAR') {
                var change = []//[[{article_data : {...}, qty: 1, table: 1, split: true || false}]]
                if (paylist == 'splitRight') {
                    for (var article of invoices) {
                        change.push({ article_data: article.article, qty: article.qty, table: this.views.paymentview.selectedTable });
                    }
                    change.push({ table: this.views.paymentview.selectedTable, split: true, finished: true });
                }
                else if (paylist == 'splitLeft') {
                    var invoices_right = this.element('splitRight').getList();
                    for (var article of invoices_right) {
                        if (article.article !== undefined && article.qty !== undefined) {
                            change.push({ article_data: article.article, qty: -article.qty, table: this.views.paymentview.selectedTable });
                        }
                    }
                    change.push({ table: this.views.paymentview.selectedTable, split: false, finished: true });
                }
                this.views.paymentview.invoice_changes_list[paymentview.invoice_changes_list.length - 1] = change;
                this.views.paymentview.setInvoiceChangesSQLDB();
                this.views.paymentview.invoice_changes_list.push([]);

                this.invoiceRight = this.element('splitRight').getList();
                this.invoiceLeft = this.element('splitLeft').getList();
                var articles = [];
                var invoices_remain;
                if (paylist == 'splitRight') {
                    var invoices_remain = this.element('splitLeft').getList();
                }
                else {
                    var invoices_remain = this.element('splitRight').getList();
                }
                for (var i in invoices_remain) {
                    var invoice = invoices_remain[i];
                    if (invoice.article !== undefined) {
                        articles.push({ article: invoice.article, qty: invoice.qty, itemID: invoice.qty });
                    }
                    else {
                        articles = [];
                    }
                }
                console.log('Invoices NOW:', this.views.paymentview.invoices);
                console.log('Show Invoices NOW:', invoices);
                console.log('Articles Before:', articles);
                console.log('Articles NOW:', articles);
                for (var i in this.views.paymentview.invoices) {
                    if (this.views.paymentview.invoices[i].table == this.views.paymentview.selectedTable) {
                        if (articles.length == 0) {
                            this.views.paymentview.invoices.splice(i, 1);
                        } else {
                            this.views.paymentview.invoices[i].articles = articles;
                        }
                        break;
                    }
                }
                this.views.paymentview.setInvoiceSQLDB();
                var price_sum = 0;
                if (invoices.length > 0) {
                    try {
                        for (var article of invoices) {
                            price_sum += parseFloat(article.article.article_price) * article.qty;
                        }
                    }
                    catch {
                        return;
                    }
                    invoices.push({
                        type: 'textline',
                        lineitem: [
                            { start: 0.05, end: 0.95, displaytext: '=' },
                        ]
                    });
                    invoices.push({
                        type: 'text',
                        lineitem: [
                            { location: 0.05, align: 'right', displaytext: 'Summe:' },
                            { location: 0.95, align: 'left', displaytext: centToShowable(price_sum) },
                        ]
                    });
                    invoices.push({
                        type: 'text',
                        lineitem: [
                            { location: 0.05, align: 'right', displaytext: 'BAR' },
                        ]
                    });
                    this.element(paylist).setList(invoices);
                }
            }
        }
    }

    createElements = () => {
        this.addElement('Button', {
            displaytext: '< Back', background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', font_size: 30, hover_border: '#009dff', grd_type: 'vertical',
            x: 30, y: 810, height: 70, width: 150, border_width: 3, border_radius: 10,
            callback: () => {
                this.invoiceLeft = this.element('splitLeft').getList();
                this.invoiceRight = this.element('splitRight').getList();
                var main_invoice = this.invoiceLeft;
                if (this.invoiceRight[this.invoiceRight.length - 1] !== undefined) {
                    if (this.invoiceRight[this.invoiceRight.length - 1].lineitem[0].displaytext != 'BAR') {
                        this.invoiceRight = this.element('splitRight').getList();
                        if (main_invoice[main_invoice.length - 1] !== undefined) {
                            if (main_invoice[main_invoice.length - 1].lineitem[0].displaytext != 'BAR') {
                                main_invoice = [...main_invoice, ...this.invoiceRight];
                            }
                            else {
                                main_invoice = this.invoiceRight;
                            }
                        }
                        else {
                            main_invoice = this.invoiceRight;
                        }
                    }
                }
                this.views.paymentview.element('paylist').setList(main_invoice);
                for (var i in this.views.paymentview.show_invoices) {
                    var invoice = this.views.paymentview.show_invoices[i];
                    if (invoice.table == this.views.paymentview.selectedTable) {
                        invoice.invoice = main_invoice;
                    }
                }
                this.invoiceLeft = [];
                this.invoiceRight = [];
                this.element('splitRight').setList([]);
                this.element('splitLeft').setList([]);
                this.setActive(false);
                this.views.paymentview.setActive(true);
            }
        });
        this.addElement('PayList', {
            name: 'splitRight',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 725, y: 50, width: 650, height: 700, scrollbarwidth: 30, scrollbarbackground: '#A9A9A9', hover_border: '#A9A9A9',
            pagescrollbuttonheight: 35, callback: this.moveLeft,
            elementOptions: {
                selectedBackground: '#00ffff',
                height: 30,
                font_size: 25,
            }
        });
        this.addElement('PayList', {
            name: 'splitLeft',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 25, y: 50, width: 650, height: 700, scrollbarwidth: 30, scrollbarbackground: '#A9A9A9', hover_border: '#A9A9A9',
            pagescrollbuttonheight: 35,
            callback: this.moveRight,
            elementOptions: {
                selectedBackground: '#00ffff',
                height: 30,
                font_size: 25,
            }
        });
        this.addElement('Button', {
            displaytext: 'BAR',
            background: ['#c9f7c8', '#10ff0c'],
            foreground: '#000000', border: '#10ff0c', border_radius: 3,
            x: 1265, y: 810, height: 70, width: 100, hover_border: '#ffffff',
            border_width: 3, grd_type: 'vertical', font_size: 30,
            callbackData: 'splitRight',
            callback: this.createInvoice
        });
        this.addElement('Button', {
            displaytext: 'BAR',
            background: ['#c9f7c8', '#10ff0c'],
            foreground: '#000000', border: '#10ff0c', border_radius: 3,
            x: 565, y: 810, height: 70, width: 100, hover_border: '#ffffff',
            border_width: 3, grd_type: 'vertical', font_size: 30,
            callbackData: 'splitLeft',
            callback: this.createInvoice
        });
        this.addElement('Button', {
            displaytext: _trquote('Rebook Table'),
            background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', hover_border: '#009dff',
            x: 355, y: 810, height: 70, width: 200, hover_border: '#009dff',
            border_width: 3, grd_type: 'vertical', font_size: 25,
            callbackData: 'splitLeft',
            callback: this.rebookTable
        });
        this.addElement('Button', {
            displaytext: _trquote('Rebook Table'),
            background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', hover_border: '#009dff',
            x: 1055, y: 810, height: 70, width: 200, hover_border: '#009dff',
            border_width: 3, grd_type: 'vertical', font_size: 25,
            callbackData: 'splitRight',
            callback: this.rebookTable
        });
        this.addElement('TextBox', {
            background: ['#a9a9a9'],
            foreground: '#000000',
            x: 25, y: 790, height: 107, width: 650,
        });
        this.addElement('TextBox', {
            background: ['#a9a9a9'],
            foreground: '#000000',
            x: 725, y: 790, height: 107, width: 650,
        });
        this.addElement('Text', {
            displaytext: _trquote('Split:'), x: 25, y: 20, font_size: 30,
        });
        this.addElement('Text', {
            displaytext: _trquote('⇋'), x: 685, y: 395, font_size: 40,
        });
    }
    setSplitActive = (state) => {
        //this.createdRightInvoice = false;
        this.setActive(state);
        for (var invoice of [...this.views.paymentview.show_invoices]) {
            if (invoice.table == this.views.paymentview.selectedTable) {
                this.invoiceLeft = [...invoice.invoice];
                try {
                    if (invoice.invoice[invoice.invoice.length - 1].lineitem[0].displaytext != 'BAR') {
                        this.element('splitLeft').setList([...invoice.invoice]);
                    }
                    else {
                        this.element('splitLeft').setList([]);
                    }
                }
                catch {
                    this.element('splitLeft').setList([]);
                }

            }
        }
    }

    load = (views) => {
        this.views = views;
    }
    gotMessage = (msg) => {
    }
    sendData = () => {
    }
}