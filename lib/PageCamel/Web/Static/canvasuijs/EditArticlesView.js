class EditArticlesView extends UIView {
    constructor(canvas) {
        super(canvas);
        this.selectedMenu = [];
    }
    createElements = () => {
        this.addElement('Line', {
            background: '#000000', x: 638, y: 0, width: 0, height: 900, thickness: 3
        });
        this.addElement('Line', {
            background: '#000000', x: 638, y: 267, width: 770, height: 0, thickness: 3
        });
        this.addElement('List', {
            name: 'categories',
            x: 650, y: 50, width: 720, height: 220, font_size: 25, scrollbarwidth: 30,
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
            x: 650, y: 275, width: 720, height: 600, font_size: 25, scrollbarwidth: 40,
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
    }
    setArticleList = (index) => {
        //when new category selected
        var article_list = []
        var articles = this.selectedMenu.categories[index.category_index].articles;
        for (var article of articles) {
            article_list.push({
                displaytext: article.article_name + '\n' + article.article_price,
                background: [article.backgroundcolor],
                foreground: getForegroundColor(article.backgroundcolor),
                callback: () => {

                },
                callbackData: article
            });
        }
        this.element('articles').setList(article_list);
    }
    setCategoriesList = () => {
        var categories_list = [];
        for (var category_index in this.selectedMenu.categories) {
            var category = this.selectedMenu.categories[category_index];
            categories_list.push({
                displaytext: category.categoryname, background: [category.backgroundcolor],
                callbackData: { category_index: category_index },
                foreground: getForegroundColor(category.backgroundcolor),
                callback: this.setArticleList,
            });
        }
        this.element('categories').setList(categories_list);
    }
    setSelectedMenu = (menu) => {
        this.selectedMenu = menu;
        this.setCategoriesList();
    }
    load = () => {
    }
    gotMessage = (msg) => {
    }
    sendData = () => {
    }
}