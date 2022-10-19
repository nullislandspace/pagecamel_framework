import * as cxv from './cxviews/cxviews.js';
import * as cxa from './cxadds/cxadds.js';
import { CXButton } from './cxelements/cxbutton.js';
declare var window: any;
var temporary_tables = [
    {
        "default_cursor": "default",
        "show_resize_frame": false,
        "resizeable": false,
        "move_dragndrop": false,
        "minWidthHeight": 25,
        "border_color": "black",
        "background_color": "green",
        "hover_border_color": "black",
        "hover_background_color": "green",
        "hover_text_color": "black",
        "allow_hover": false,
        "text_color": "black",
        "font_family": "Arial",
        "text": "2",
        "text_alignment": "center",
        "auto_line_break": true,
        "font_size": 0.5,
        "gradient": [
            ""
        ],
        "background_image": "",
        "border_radius": 0,
        "border_width": 15,
        "border_relative": false,
        "width": 0.2304878048780488,
        "height": 0.2731707317073171,
        "xpos": 0.7695121951219512,
        "ypos": 0.7268292682926829,
        "is_relative": true,
        "has_changed": false,
        "xpixel": 631,
        "ypixel": 447,
        "widthpixel": 189,
        "heightpixel": 168,
        "active": true,
        "name": "2"
    },
    {
        "default_cursor": "default",
        "show_resize_frame": false,
        "resizeable": false,
        "move_dragndrop": false,
        "minWidthHeight": 25,
        "border_color": "black",
        "background_color": "green",
        "hover_border_color": "black",
        "hover_background_color": "green",
        "hover_text_color": "black",
        "allow_hover": false,
        "text_color": "black",
        "font_family": "Arial",
        "text": "0",
        "text_alignment": "center",
        "auto_line_break": true,
        "font_size": 0.5,
        "gradient": [
            ""
        ],
        "background_image": "",
        "border_radius": 0,
        "border_width": 15,
        "border_relative": false,
        "width": 0.2304878048780488,
        "height": 0.2731707317073171,
        "xpos": 0,
        "ypos": 0.7268292682926829,
        "is_relative": true,
        "has_changed": false,
        "xpixel": 0,
        "ypixel": 447,
        "widthpixel": 189,
        "heightpixel": 168,
        "active": true,
        "name": "0"
    }
];

let devicePixelRatio = window.devicePixelRatio || 1;
let dpi_x = /*document.getElementById('testdiv')!.offsetWidth * */devicePixelRatio;
let dpi_y = /*document.getElementById('testdiv')!.offsetHeight * */devicePixelRatio;

var table_list: cxa.CXTable[] = [];
const min_dpi = 96;
const min_width = 1024;
const min_height = 768;
// console.log(dpi_x, dpi_y);

// Adds the canvas element to the document.
let viewelements: any[] = [];

const htmlcnv = document.getElementById("CXcanvas") as HTMLCanvasElement;
const ctx = htmlcnv.getContext("2d") as CanvasRenderingContext2D; //canvas context

function initialize() {
    // Register an event listener to call the resizeCanvas() function 
    // each time the window is resized.
    window.addEventListener('resize', resizeCanvas, false);
    // Register an event lister to call the drawLine() function
    // each time the user clicks the left mouse
    htmlcnv.addEventListener('mousedown', onEvent, false);
    htmlcnv.addEventListener('mousemove', onEvent, false);
    htmlcnv.addEventListener('mouseup', onEvent, false);
    htmlcnv.addEventListener('mouseleave', onEvent, false);
    document.addEventListener('keydown', onEvent, false);
    // Draw canvas border for the first time.
    resizeCanvas();
}

function onEvent(e: Event) {

    let reDR = false;
    //console.log("Event-Type: " + e.type);
    for (let i = 0; i < viewelements.length; ++i) {
        if (viewelements[i].checkEvent(e)) {
            viewelements[i].handleEvent(e);
            if (viewelements[i].has_changed) {
                reDR = true;
            }
        }
    }
    if (reDR) {
        drawCanvas();
    }
}

// Runs each time the DOM window resize event fires.
// Resets the canvas dimensions to match window,
// then draws the new borders accordingly.
function resizeCanvas() {
    let w = window.innerWidth;
    let h = window.innerHeight;
    if (w < min_width) {
        w = min_width;
    }

    if (h < min_height) {
        h = min_height;
    }

    if (dpi_x > min_dpi || dpi_y > min_dpi) {
        w = Math.round(w * dpi_x / min_dpi);
        h = Math.round(h * dpi_y / min_dpi);
    }


    if (w < (4 / 3 * h)) {
        h = 3 / 4 * w;
    }
    else {
        w = 4 / 3 * h;
    }
    //console.log("New w,h: " + w.toString() + "," + h.toString());
    htmlcnv.width = w;
    htmlcnv.height = h;
    drawCanvas();
}

// Redraw canvas.
function drawCanvas() {
    // Clear the entire canvas
    ctx.clearRect(0, 0, htmlcnv.width, htmlcnv.height);
    ctx.fillStyle = "#b3b3b3ff";
    ctx.fillRect(0, 0, htmlcnv.width, htmlcnv.height);
    console.log("drawing Viewelements");
    viewelements.forEach(viewelement => {
        viewelement.draw();
    });
}


// way of generating tables from json only temporary
function generateTableList(tableplan_tables: any[]) {
    for (let i = 0; i < tableplan_tables.length; ++i) {
        let table = new cxa.CXTable();
        table.name = tableplan_tables[i].name;
        table.number = Number(tableplan_tables[i].name);
        table_list.push(table);
    }
    return table_list;
}


export function cxposmainext() {
    initialize();
    //var table = new cxa.CXTable();
    //table.name = "Tisch 1";
    //table.number = 1;
    let tableplan = new cxv.CXTablePlanView(ctx);
    tableplan.tables = temporary_tables;
    //tableplan.active = false;
    var posview = new cxv.CXPosView(ctx);

    posview.pcwebsocket = window.pcws;
    console.log("got websocket", window.pcws);
    console.log("set websocket", posview.pcwebsocket);
    posview.processArticlesCB = function () {
        console.log("Got articles");
    }
    // posview.sendMsgGetArticles();

    posview.active = false;
    tableplan.onAddImageClick = function () {
        cxa.openImageFileDialog('upload', tableplan.onImageSelected);
    }
    tableplan.onAddBackgroundImageClick = function () {
        cxa.openImageFileDialog('upload', tableplan.onBackgroundImageSelected);
    }
    var table_list = generateTableList(temporary_tables); // list of tables

    tableplan.onTableSelected = (obj: CXButton) => {
        table_list.forEach(table => {
            if (String(table.number) == obj.name) { // select table where the name matches
                // posview.selectedTable = table;
            }
        });
        posview.active = true;
        tableplan.active = false;
        drawCanvas();
    };
    viewelements.push(posview);
    viewelements.push(tableplan);
    drawCanvas();

    var test_table: cxa.CXTable = new cxa.CXTable();
    test_table.makeOrderList([{ article: {}, quantity: 1, booked: false, id: 1, timestamp: 0 }, { article: {}, quantity: 1, booked: false, id: 1, timestamp: 0 }]);
}