class PaymentView extends UIView {
    constructor(canvas) {
        super(canvas);
        this.menu_list = [];
        this.invoice_changes_list = []; //[[{article_data : {...}, qty: 1, table: 1}, true || false]] //invoice changes for server
        this.invoices = [] //[{table: 1, articles : [{article: ----, qty: 1}]}] // for saving invoices locally and getting them from server
        this.show_invoices = []; //[{table: 1, invoice: []}] //invoices for showing
        this.selectedTable = 0;
        this.selectedMenu;
    }
    getForegroundColor = (hex_color) => {
        var rgb_color = HexToRGB(hex_color);
        var foreground = (rgb_color[0] + rgb_color[1] + rgb_color[2]) / 3;
        if (foreground > 100) {
            foreground = 0;
        }
        else {
            foreground = 255
        }
        var hex_foreground = '#' + RGBToHex(foreground, foreground, foreground);
        return hex_foreground;
    }

    invoiceChangeHandler = (article, qty) => {
        this.invoice_changes_list[this.invoice_changes_list.length - 1].push({ article: article, qty: qty, table: this.selectedTable });
    }

    addToInvoice = (article) => {
        this.invoiceChangeHandler(article, 1);
        var invoice_list = [];
        //get invoice_list from Invoices
        for (var i in this.show_invoices) {
            var invoice = this.show_invoices[i];
            if (invoice.table == this.selectedTable) {
                invoice_list = this.show_invoices[i].invoice;
            }
        }
        if (invoice_list.length > 0) {
            if (invoice_list[invoice_list.length - 1].lineitem[0].displaytext == 'BAR') {
                invoice_list = [];
            }
        }
        invoice_list.push({
            article: article,
            qty: 1,
            type: 'text',
            lineitem: [
                { location: 0.05, align: 'right', displaytext: 'TO' },
                { location: 0.3, align: 'right', displaytext: article.article_name },
                { location: 0.95, align: 'left', displaytext: article.article_price },
            ]
        });
        this.element('paylist').setList(invoice_list);

        //add invoice_list to Invoices
        for (var i in this.show_invoices) {
            var invoice = this.show_invoices[i];
            if (invoice.table == this.selectedTable) {
                this.show_invoices[i].invoice = invoice_list;
                return;
            }
        }
        this.show_invoices.push({ table: this.selectedTable, invoice: invoice_list });
    }

    setArticleList = (index) => {
        //when new category selected
        var article_list = []
        var articles = this.menu_list[index.menu_index].categories[index.category_index].articles;
        for (var article of articles) {
            article_list.push({
                displaytext: article.article_name + '\n' + article.article_price,
                background: [article.backgroundcolor],
                foreground: this.getForegroundColor(article.backgroundcolor),
                callback: this.addToInvoice,
                callbackData: article
            });
        }
        this.element('articles').setList(article_list);
    }
    setInvoiceChangesSQLDB = () => {
        executeSQL("DELETE FROM invoice_changes");
        executeSQL("INSERT INTO invoice_changes(data)\
            VALUES (?);", JSON.stringify(this.invoice_changes_list));
    }
    setInvoiceSQLDB = () => {
        executeSQL("DELETE FROM invoices");
        executeSQL("INSERT INTO invoices (data)\
            VALUES (?);", JSON.stringify(this.invoices));
    }
    setCategoriesList = () => {
        var categories_list = [];
        for (var menu_index in this.menu_list) {
            var menu = this.menu_list[menu_index];
            if (this.selectedMenu == menu.menu_name) {
                for (var category_index in menu.categories) {
                    var category = menu.categories[category_index];
                    categories_list.push({
                        displaytext: category.categoryname, background: [category.backgroundcolor],
                        callbackData: { menu_index: menu_index, category_index: category_index },
                        foreground: this.getForegroundColor(category.backgroundcolor),
                        callback: this.setArticleList,
                    });
                }
                break;
            }
        }
        this.element('categories').setList(categories_list);
    }
    createElements = (mainview) => {
        this.addElement('Text', {
            name: 'selectedTable',
            displaytext: 'Table:',
            background: ['#000000'],
            x: 20, y: 25, font_size: 30
        });
        this.addElement('Button', {
            displaytext: '< Back', background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', font_size: 30, hover_border: '#009dff', grd_type: 'vertical',
            x: 20, y: 810, height: 70, width: 150, border_width: 3, border_radius: 10,
            callback: () => {
                if (this.invoice_changes_list[this.invoice_changes_list.length - 1].length < 1) {
                    this.invoice_changes_list.pop()
                }
                else {
                    this.invoice_changes_list[this.invoice_changes_list.length - 1].push({ table: this.selectedTable, finished: false });
                    this.setInvoiceChangesSQLDB();
                    for (var i in this.invoices) {
                        var changed_invoice = this.invoices[i];
                        if (changed_invoice.table == this.selectedTable) {
                            changed_invoice.articles = [];
                            for (var j in this.element('paylist').getList()) {
                                var list_item = this.element('paylist').getList()[j];
                                changed_invoice.articles.push({ article: list_item.article, qty: list_item.qty });
                            }
                            this.setInvoiceSQLDB();
                            break;
                        }
                    }
                }
                this.setActive(false);
                for (var invoice of this.invoices) {
                    if (Math.floor(invoice.table) == this.selectedTable && invoice.articles.length > 0) {
                        mainview.setTableView(true);
                        return;
                    }
                }
                mainview.setTableView(false);
            }
        });
        this.addElement('PayList', {
            name: 'paylist',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 25, y: 50, width: 600, height: 300, scrollbarwidth: 30, scrollbarbackground: '#A9A9A9', hover_border: '#A9A9A9',
            pagescrollbuttonheight: 35,
            elementOptions: {
                selectedBackground: '#00ffff',
                height: 30,
                font_size: 25,
            }
        });
        this.addElement('List', {
            name: 'categories',
            x: 650, y: 50, width: 750, height: 220, font_size: 25, scrollbarwidth: 30,
            elementOptions: {
                border: '#10ff0c',
                hover_border: '#ffffff',
                border_width: 3,
                height: 100,
                width: 100,
                gap: 10,
                font_size: 15,
                border_radius: 10,
            }
        });
        this.addElement('List', {
            name: 'articles',
            x: 650, y: 275, width: 750, height: 500, font_size: 25, scrollbarwidth: 30,
            elementOptions: {
                border: '#10ff0c',
                hover_border: '#ffffff',
                border_width: 3,
                height: 100,
                width: 100,
                gap: 10,
                font_size: 15,
                border_radius: 10,
            }
        });
        this.addElement('TextBox', {
            name: 'paymentTextInput',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 25, y: 370, width: 350, height: 80, font_size: 50, align: 'right'
        });
        this.addElement('Numpad', {
            show_keys: { x: true, ZWS: true },
            background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000',
            grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
            x: 25, y: 460, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
            callback: (val) => {
                var obj = this.element('paymentTextInput');
                var obj_text = obj.getText();
                if (val.value == ',') {
                    if (!obj_text.includes(',')) {
                        obj_text = obj_text + val.value
                        obj.setText(obj_text);
                    }
                }
                if (val.value >= 0) {
                    if (obj_text.includes(',')) {
                        var index = obj_text.indexOf(',');
                        if (index + 3 > obj_text.length) {
                            obj.setText(obj_text + val.value);
                        }
                    } else {
                        obj.setText(obj_text + val.value);
                    }

                }
                else if (val.value == '⌫') {
                    obj_text = obj_text.slice(0, -1)
                    obj.setText(obj_text);
                }
                if (val.value == '+/-' && this.element('paylist').getSelectedItemIndex) {
                    var paylist = this.element('paylist').getList();
                    var selected_index = this.element('paylist').getSelectedItemIndex();
                    this.invoiceChangeHandler(paylist[selected_index].article, -1);
                    this.element('paylist').deleteSelected();
                }
            }
        });

        this.addElement('Button', {
            displaytext: this.selectedMenu, name: 'buttonmenu',
            x: 500, y: 370, width: 125, height: 50,
            foreground: '#000000', border_radius: 10, border_width: 2,
            background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            font_size: 20, hover_border: '#009dff', grd_type: 'vertical',
            callback: () => {
                this.addElement('Dialog', {
                    displaytext: 'Select Menu:',
                    background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'selectMenu',
                    hover_border: '#32d600', border_width: 3, width: 700, height: 400,
                    alpha_x: 0, alpha_y: 0, alpha_width: 1400, alpha_height: 900,
                    type: 'select',
                    callback: (action) => {
                        if (action == 'cancel') {
                            this.dialog.clear();
                        }
                        else {
                            this.selectedMenu = this.menu_list[this.element('selectMenu').getSelectedItemIndex()].menu_name;
                            this.element('buttonmenu').displaytext = this.selectedMenu;
                            this.setCategoriesList();
                            this.element('articles').setList([]);
                            this.dialog.clear();
                        }
                    },
                });
                var menu_select_list = [];
                for (var menu of this.menu_list) {
                    menu_select_list.push({
                        type: 'text',
                        lineitem: [
                            { location: 0.05, align: 'right', displaytext: menu.menu_name },
                        ]
                    });
                }
                this.element('selectMenu').setList(menu_select_list);
            }
        });
        this.addElement('Button', {
            displaytext: 'BAR',
            background: ['#c9f7c8', '#10ff0c'],
            foreground: '#000000', border: '#10ff0c', border_radius: 3,
            x: 225, y: 664, width: 60, height: 128, hover_border: '#ffffff',
            border_width: 3, grd_type: 'vertical', font_size: 20,
            callback: () => {
                var invoices = this.element('paylist').getList();
                var price_sum = 0;
                if (invoices.length > 0) {
                    try {
                        for (var article of invoices) {
                            price_sum += parseFloat(article.lineitem[2].displaytext);
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
                            { location: 0.95, align: 'left', displaytext: price_sum },
                        ]
                    });
                    invoices.push({
                        type: 'text',
                        lineitem: [
                            { location: 0.05, align: 'right', displaytext: 'BAR' },
                        ]
                    });
                    this.invoice_changes_list[this.invoice_changes_list.length - 1].push({ table: this.selectedTable, finished: true });
                    this.setInvoiceChangesSQLDB();
                    this.invoice_changes_list.push([]);
                    this.element('paylist').setList(invoices);

                    for (var i in this.invoices) {
                        var changed_invoice = this.invoices[i]
                        if (changed_invoice.table == this.selectedTable) {
                            this.invoices.splice(i, 1);
                        }
                        this.setInvoiceSQLDB();
                    }
                }
            }
        });
        this.addElement('Text', {
            displaytext: 'Karte:',
            background: ['#000000'],
            x: 420, y: 395, font_size: 30
        });
        this.setCategoriesList();
    }
    convertInvoicesToShowableInvoices = () => {
        this.show_invoices = [];
        for (var invoice of this.invoices) {
            this.show_invoices.push({ table: invoice.table, invoice: [] });
            for (var article of invoice.articles) {
                this.show_invoices[this.show_invoices.length - 1].invoice.push({
                    article: article.article,
                    qty: article.qty,
                    type: 'text',
                    lineitem: [
                        { location: 0.05, align: 'right', displaytext: 'TO' },
                        { location: 0.3, align: 'right', displaytext: article.article.article_name },
                        { location: 0.95, align: 'left', displaytext: article.article.article_price },
                    ]
                });
            }
            if (this.show_invoices[this.show_invoices.length - 1].table == this.selectedTable) {
                this.element('paylist').setList(this.show_invoices[this.show_invoices.length - 1].invoice);
            }
        }
    }
    load = (default_menu) => {
        this.selectedMenu = default_menu;
        executeSQL("CREATE TABLE IF NOT EXISTS articles(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);");
        executeSQL("CREATE TABLE IF NOT EXISTS invoices(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);");
        executeSQL("CREATE TABLE IF NOT EXISTS invoice_changes(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);");
        var menus = executeSQL("SELECT data FROM articles");
        if (menus[0] !== undefined && menus[0].data !== undefined) {
            this.menu_list = JSON.parse(menus[0].data);
            console.log('LOCAL ARTICLES', this.menu_list);
        }

        var invoice_changes = executeSQL("SELECT data FROM invoice_changes;");
        if (invoice_changes[0] !== undefined) {
            this.invoice_changes_list = JSON.parse(invoice_changes[0].data);
        }
            sendMessage({
                type: 'GETARTICLES'
            });
    }
    gotMessage = (msg) => {
        if (msg.type == 'ARTICLES') {
            executeSQL("DELETE FROM articles");
            executeSQL("INSERT INTO articles (data)\
                VALUES (?);", JSON.stringify(msg.data));
            this.menu_list = msg.data;
            console.log("Got new ARTICLES from server:", msg.data);

        }
    }
    sendData = () => {

    }
    billTable = (number, invoices) => {
        this.invoices = invoices;
        this.convertInvoicesToShowableInvoices();
        this.selectedTable = number;
        this.setActive(true);
        this.element('selectedTable').setText('Table: ' + number);
        this.invoice_changes_list.push([]);
        console.log(this.invoice_changes_list);
        var invoice_list = [];
        for (var i in this.show_invoices) {
            var invoice = this.show_invoices[i];
            if (invoice.table == this.selectedTable) {
                invoice_list = this.show_invoices[i].invoice;
            }
        }
        this.element('paylist').setList(invoice_list);
        for (var i in this.invoices) {
            var changed_invoice = this.invoices[i]
            if (changed_invoice.table == this.selectedTable) {
                return;
            }
        }
        this.invoices.push({ table: number, articles: [] });
    }
}