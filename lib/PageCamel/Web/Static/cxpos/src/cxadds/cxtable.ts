interface OrderItem {
    id: number,
    timestamp: number,
    article: {}, quantity:
    number,
    booked: boolean,
    toStringArray: Function
};
interface OrderList {
    toStringArray: Function,
    order_items: OrderItem[],
    sum: Function,
    addOrderItem: Function,
    deleteOrderItem: Function
};
interface OrderArticle {
}
export function createOrderItem(article: {}, id: number = 0, timestamp: number = Date.now(), quantity: number = 1, booked: boolean = false) {
    var obj: OrderItem = {
        id: id,
        timestamp: timestamp,
        article: article,
        quantity: quantity,
        booked: booked,
        toStringArray: function (params: string[]) {
        }
    }
    return obj;
}
export function createOrderList(order_items: []) {
    var items = order_items.map(function (item: OrderItem) {
        return createOrderItem(item.article, item.id, item.timestamp, item.quantity, item.booked);
    });
    var obj: OrderList = {
        order_items: items,
        toStringArray: function (params: string[]) {
        },
        sum: function () {
        },
        addOrderItem: function (order_item: OrderItem) {
        },
        deleteOrderItem: function (order_item: OrderItem) {
        }
    }
    return obj;
}
export class CXTable {
    protected _order_list: OrderList = createOrderList([]);
    protected _name: string = "";
    protected _number: number | null = null;
    protected _visible: boolean = true;
    protected _parentnumber: number = 0;
    protected _booked: boolean = false;
    /**
     * array of order items
     */
    set order_list(order_items: []) {
        this._order_list = createOrderList(order_items);
    }
    /**
     * @todo: needs to return order list
     */
    get order_list(): [] {
        return [];
        //return this._order_list;
    }
    /**
     * Add orders to the order list
     * @param orders
     */
    addOrders(orders: string[]) {
    }
    /**
     * Remove orders from the order list
     * @param orders
     */
    removeOrders(orders: string[]) {
    }
    set name(name: string) {
        this._name = name;
    }
    get name(): string {
        return this._name;
    }
    set number(number: number | null) {
        this._number = number;
    }
    get number(): number | null {
        return this._number;
    }
    set visible(visible: boolean) {
        this._visible = visible;
    }
    get visible(): boolean {
        return this._visible;
    }
    set parentnumber(number: number) {
        this._parentnumber = number;
    }
    get parentnumber(): number {
        return this._parentnumber;
    }
    get booked(): boolean {
        return this._booked;
    }
}
//var item = Object.create(OrderItem);
//item.id = 1;
//console.log(item.id);

