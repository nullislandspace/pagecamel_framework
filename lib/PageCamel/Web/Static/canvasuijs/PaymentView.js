class PaymentView extends UIView {
    constructor(canvas) {
        super(canvas);
        this.menu_list = [];
        this.selectedMenu;
    }
    setArticleList = (category_index) => {
        var article_list = []
        for (var article of menu.categories) {
            console.log(article);
            
        }
    }
    setCategoriesList = () => {
        var categories_list = [];
        for (var menu of this.menu_list) {
            if (this.selectedMenu == menu.menu_name) {
                for (var i in menu.categories) {
                    var category = menu.categories[i];
                    categories_list.push({
                        displaytext: category.categoryname, background: [category.backgroundcolor],
                        callbackData: i,
                        callback: this.setArticleList,
                    });
                }
            }
        }
        console.log(categories_list);
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
            name: 'categories',
            x: 650, y: 50, width: 750, height: 220, font_size: 25, scrollbarwidth: 30,
            elementOptions: {
                foreground: '#000000',
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
                foreground: '#000000',
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
                        console.log(action);
                        if (action == 'cancel') {
                            this.dialog.clear();
                        }
                        else {
                            this.selectedMenu = this.menu_list[this.element('selectMenu').getSelectedItemIndex()].menu_name;
                            this.element('buttonmenu').displaytext = this.selectedMenu;
                            this.setCategoriesList();
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
        this.addElement('Text', {
            displaytext: 'Karte:',
            background: ['#000000'],
            x: 420, y: 395, font_size: 30
        });
        this.setCategoriesList();


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