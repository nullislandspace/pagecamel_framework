import * as cxv from './cxviews/cxviews.js';
import * as cxa from './cxadds/cxadds.js';


let devicePixelRatio = window.devicePixelRatio || 1;
let dpi_x = /*document.getElementById('testdiv')!.offsetWidth * */devicePixelRatio;
let dpi_y = /*document.getElementById('testdiv')!.offsetHeight * */devicePixelRatio;

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
    for (let i = 0; i < viewelements.length; ++i) {
        viewelements[i].draw();
    }
}

export function cxposmainext() {
    initialize();
    var table = new cxa.CXTable();
    table.name = "Tisch 1";
    table.number = 1;

    let tableplan = new cxv.CXTablePlanView(ctx);
    console.log(window);
    
    viewelements.push(tableplan);
    drawCanvas();
}
