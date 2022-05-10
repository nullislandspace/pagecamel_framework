class PaymentView extends UIView {
    constructor(canvas) {
        super(canvas);
    }
    createElements = () => {
        this.addElement('Text', {
            name: 'selectedTable',
            displaytext: 'Table:',
            background: ['#000000'],
            x: 20, y: 20, font_size: 30
        });
    }
    load = () => {

    }
    gotMessage = (msg) => {

    }
    sendData = () => {

    }
    billTable = (number) => {
        this.setActive(true);
        this.element('selectedTable').setText('Table: ' + number);
    }
}