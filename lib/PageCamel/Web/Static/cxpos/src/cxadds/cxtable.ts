interface OrderItem {
    id: number,
    timestamp: number,
    article: OrderArticle,
    quantity: number,
    booked: boolean,
    toStringArray: (val: string[]) => string[]
};
interface OrderList {
    toStringArray: (val: string[]) => string[],
    orderItems: OrderItem[],
    sum: () => number,
    addOrderItem: (val: OrderItem) => void,
    deleteOrderItem: (index: number) => void
};
interface OrderArticle {
}
export function createOrderItem(article: OrderArticle, id: number = 0, timestamp: number = Date.now(), quantity: number = 1, booked: boolean = false): OrderItem {
    var obj: OrderItem = {
        id: id,
        timestamp: timestamp,
        article: article,
        quantity: quantity,
        booked: booked,
        toStringArray: function (params: string[]) {
            return params;
        }
    }
    return obj;
}
export function createOrderList(OrderItems: []) {
    var items = OrderItems.map(function (item: OrderItem) {
        return createOrderItem(item.article, item.id, item.timestamp, item.quantity, item.booked);
    });
    var obj: OrderList = {
        orderItems: items,
        toStringArray: function (params: string[]) {
            return params;
        },
        sum: function () {
            return 0;
        },
        addOrderItem: function (val: OrderItem) {
        },
        deleteOrderItem: function (index: number) {

        }
    }
    return obj;
}
export class CXTable {
    protected _orderList: OrderList = createOrderList([]);
    protected _name: string = "";
    protected _number: number | null = null;
    protected _visible: boolean = true;
    protected _parentnumber: number = 0;
    protected _booked: boolean = false;
    /**
     * array of order items
     */
    set orderList(orderItems: []) {
        this._orderList = createOrderList(orderItems);
    }
    /**
     * @todo: needs to return order list
     */
    get orderList(): [] {
        return [];
        //return this._;
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

