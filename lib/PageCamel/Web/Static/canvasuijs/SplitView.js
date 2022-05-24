class SplitView extends UIView {
    constructor(canvas) {
        super(canvas);
        this.views;
        this.invoiceLeft = { invoice: [] };
        this.invoiceRight = { invoice: [] };
    }
    moveLeft = (id) => {
        if (this.invoiceRight[id] !== undefined) {
            this.invoiceLeft = [...this.element('splitLeft').getList()];
            this.invoiceRight = [...this.element('splitRight').getList()];
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
                    console.log('invoiceLeft:', [...this.element('splitLeft').getList()], 'invoiceRight:', [...this.element('splitRight').getList()]);
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
            console.log('invoiceLeft:', [...this.element('splitLeft').getList()], 'invoiceRight:', [...this.element('splitRight').getList()]);
        }
    }
    moveRight = (id) => {
        if (this.invoiceLeft[id] !== undefined) {
            this.invoiceLeft = [...this.element('splitLeft').getList()];
            this.invoiceRight = [...this.element('splitRight').getList()];
            for (var invoice of this.invoiceRight) {
                if (invoice.itemID == this.invoiceLeft[id].itemID) {
                    invoice.qty += 1;
                    this.invoiceLeft[id].qty -= 1;
                    if (this.invoiceLeft[id].qty <= 0) {
                        this.invoiceLeft.splice(id, 1);
                    }
                    this.element('splitLeft').setList([...this.invoiceLeft]);
                    this.element('splitRight').setList([...this.invoiceRight]);
                    console.log('invoiceLeft:', [...this.element('splitLeft').getList()], 'invoiceRight:', [...this.element('splitRight').getList()]);
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
            console.log('invoiceLeft:', [...this.element('splitLeft').getList()], 'invoiceRight:', [...this.element('splitRight').getList()]);

        }
    }
    createElements = () => {
        this.addElement('Button', {
            displaytext: '< Back', background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', font_size: 30, hover_border: '#009dff', grd_type: 'vertical',
            x: 30, y: 810, height: 70, width: 150, border_width: 3, border_radius: 10,
            callback: () => {
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
            callback: () => {

            }
        });
        this.addElement('Button', {
            displaytext: 'BAR',
            background: ['#c9f7c8', '#10ff0c'],
            foreground: '#000000', border: '#10ff0c', border_radius: 3,
            x: 565, y: 810, height: 70, width: 100, hover_border: '#ffffff',
            border_width: 3, grd_type: 'vertical', font_size: 30,
            callback: () => {

            }
        });
        this.addElement('Button', {
            displaytext: 'Tisch Umbuchen',
            background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', hover_border: '#009dff',
            x: 355, y: 810, height: 70, width: 200, hover_border: '#009dff',
            border_width: 3, grd_type: 'vertical', font_size: 25,
            callback: () => {
            }
        });
        this.addElement('Button', {
            displaytext: 'Tisch Umbuchen',
            background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            foreground: '#000000', hover_border: '#009dff',
            x: 1055, y: 810, height: 70, width: 200, hover_border: '#009dff',
            border_width: 3, grd_type: 'vertical', font_size: 25,
            callback: () => {
            }
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