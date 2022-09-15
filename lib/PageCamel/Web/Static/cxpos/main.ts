import { CXTable } from "./src/mycxelements/cxtable.js";
import { CXTextInput } from "./src/mycxelements/cxtextinput.js";
import { CXButton } from "./src/mycxelements/cxbutton.js";
import { CXScrollList } from "./src/mycxelements/cxscrolllist.js";
import { CXDragView } from "./src/cxdragview.js";
import { CXDropDown } from "./src/mycxelements/cxdropdown.js";
let htmlppidiv: string = `<div id='testdiv' style='height: 1in; left: -100%; position: absolute; top: -100%; width: 1in;'></div>`;
document.body.innerHTML = htmlppidiv;

let devicePixelRatio = window.devicePixelRatio || 1;
let dpi_x = document.getElementById('testdiv')!.offsetWidth * devicePixelRatio;
let dpi_y = document.getElementById('testdiv')!.offsetHeight * devicePixelRatio;

const min_dpi = 96;
const min_width = 1024;
const min_height = 768;
console.log(dpi_x, dpi_y);


document.body.onload = bodyOnLoad;


// Adds the canvas element to the document.
let viewelements: any[] = [];
let htmlcanvas: string = `<canvas id='CXcanvas' style='background-color: #b3b3b3ff; '></canvas>`;
document.body.innerHTML = htmlcanvas;

const htmlcnv = document.getElementById("CXcanvas") as HTMLCanvasElement;
const ctx = htmlcnv.getContext("2d") as CanvasRenderingContext2D; //canvas context


export function bodyOnLoad() {
    main();
    return true;
}

function initialize() {
    // Register an event listener to call the resizeCanvas() function 
    // each time the window is resized.
    window.addEventListener('resize', resizeCanvas, false);
    // Register an event lister to call the drawLine() function
    // each time the user clicks the left mouse
    htmlcnv.addEventListener('click', onEvent, false);
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
    console.log("New w,h: " + w.toString() + "," + h.toString());
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
    for (let i = 0; i < viewelements.length; ++i) {
        viewelements[i].draw();
    }
}
/* interface first {
    name: string,
    age: number
}

interface second {
    product: string,
    available: boolean,
    amount: number
}

class test extends CXTable implements first, second {
    name: string;
    age: number;
    product: string;
    available: boolean;
    amount: number;
    constructor(name: string, age: number, product: string, available: boolean, amount: number) {
        super();
        this.name = name;
        this.age = age;
        this.product = product;
        this.available = available;
        this.amount = amount;
    }
    getName() {
        return this.name;
    }
} */

function main() {
    initialize();
    /*     let defaultview = new CXDragView(ctx, 0, 0, 1, 1, true, true);
        defaultview.onBackButtonClicked = () => {
            console.log("BackButtonClicked");
        }
        defaultview.background_color = "#00ff00";
        viewelements.push(defaultview); */

    let dropdown = new CXDropDown(ctx, 0.8, 0.5, 0.15, 0.2, true, false);
    dropdown.text = 'Name';
    dropdown.field_width = 0.8;
    dropdown.field_height = 0.2;
    dropdown.list = [['Test 1'], ['Test 2'], ['Test 3'], ['Test 4'], ['Test 5'], ['Test 6'], ['Test 7'], ['Test 8'], ['Test 9'], ['Test 10'], ['Test 11'], ['Test 12'], ['Test 13'], ['Test 14'], ['Test 15']];
    dropdown.background_color = '#ff0000';
    viewelements.push(dropdown);

    //let textinput = new CXTextInput(ctx, 0.1, 0.1, 0.2, 0.05, true, true);
    //textinput.border_width = 0.05;
    //let button = new CXButton(ctx, 0.1, 0.2, 0.2, 0.05, true, true);
    //button.text = "Button";
    //button.gradient = ['#ff0000ff', '#00ff00ff'];
    //button.radius = 0.05;
    //let scrolllist = new CXScrollList(ctx, 0.1, 0.3, 0.7, 0.6, true, true);
    ////generate some test data
    //let data: string[][] = [];
    //for (let i = 0; i < 100; ++i) {
    //    let row: string[] = [];
    //    for (let j = 0; j < 3; ++j) {
    //        row.push("Row " + i.toString() + " Col " + j.toString());
    //    }
    //    data.push(row);
    //}
    //scrolllist.list = data;
    //
    //viewelements.push(scrolllist);
    //viewelements.push(button);
    //viewelements.push(textinput);
    
    drawCanvas();

}