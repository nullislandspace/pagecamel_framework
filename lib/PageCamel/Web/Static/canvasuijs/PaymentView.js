class PaymentView extends UIView {
    constructor(canvas) {
        super(canvas);
        this.menu_list = [];
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
                this.setActive(false);
                mainview.setActive(true);
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
            name: 'articles',
            x: 700, y: 100, width: 800, height: 500, font_size: 25, scrollbarwidth: 60,
            callback: () => {

            },
            elementOptions: {
                background: ['#c9f7c8', '#10ff0c'],
                foreground: '#000000',
                border: '#10ff0c',
                hover_border: '#ffffff',
                border_width: 3,
                grd_type: 'vertical',
                height: 100,
                width: 100,
                gap: 10,
                font_size: 15,
                border_radius: 10
            }
        });
        this.addElement('TextInput', {
            type: 'float', name: 'paymentTextInput',
            background: ['#ffffff'], foreground: '#000000', border: '#000000', border_width: 3,
            x: 25, y: 370, width: 350, height: 80, font_size: 50, align: 'left'
        });
        this.addElement('Numpad', {
            show_keys: { x: true, ZWS: true },
            background: ['#f9a004', '#ff0202'], foreground: '#000000', border: '#FF0000',
            grd_type: 'vertical', border_width: 1, hover_border: '#ffffff',
            x: 25, y: 460, width: 200, height: 340, border_radius: 10, font_size: 20, gap: 10,
            callback: (val) => {
                var obj = this.element('paymentTextInput');
                var obj_text = obj.getText();
                if (val.value >= 0 || val.value == ',') {
                    obj_text = obj_text + val.value
                    obj.setText(obj_text);
                }
                else if (val.value == '⌫') {
                    obj_text = obj_text.slice(0, -1)
                    obj.setText(obj_text);
                }
            }
        });

        this.addElement('Button', {
            displaytext: 'Test',
            x: 500, y: 370, width: 125, height: 50,
            foreground: '#000000', border_radius: 10, border_width: 2,
            background: ['#4fbcff', '#009dff'], border: '#4fbcff',
            font_size: 20, hover_border: '#009dff', grd_type: 'vertical',
            callback: () => {
                this.addElement('Dialog', {
                    background: ['#cecece'], foreground: '#a9a9a9', border: '#39f500', name: 'label',
                    hover_border: '#32d600', border_width: 3, width: 700, height: 400,
                    alpha_x: 0, alpha_y: 0, alpha_width: 1400, alpha_height: 900,
                    type: 'select',
                    callback: () => {

                    },
                });
            }
        });
        this.addElement('Text', {
            displaytext: 'Karte:',
            background: ['#000000'],
            x: 420, y: 395, font_size: 30
        });

    }
    load = () => {
        executeSQL("CREATE TABLE IF NOT EXISTS articles(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT);");
        var menus = executeSQL("SELECT data FROM articles");
        if (menus[0] !== undefined && menus[0].data !== undefined) {
            this.menu_list = JSON.parse(menus[0].data);
            console.log('LOCAL ARTICLES', this.menu_list);
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
    billTable = (number) => {
        this.setActive(true);
        this.element('selectedTable').setText('Table: ' + number);
    }
}