import { CXTablePlanView } from "./src/cxtableplanview.js";
let htmlppidiv = `<div id='testdiv' style='height: 1in; left: -100%; position: absolute; top: -100%; width: 1in;'></div>`;
document.body.innerHTML = htmlppidiv;
let devicePixelRatio = window.devicePixelRatio || 1;
let dpi_x = document.getElementById('testdiv').offsetWidth * devicePixelRatio;
let dpi_y = document.getElementById('testdiv').offsetHeight * devicePixelRatio;
const min_dpi = 96;
const min_width = 1024;
const min_height = 768;
console.log(dpi_x, dpi_y);
document.body.onload = bodyOnLoad;
// Adds the canvas element to the document.
let viewelements = [];
let htmlcanvas = `<canvas id='CXcanvas' style='background-color: #b3b3b3ff; '></canvas>`;
document.body.innerHTML = htmlcanvas;
const htmlcnv = document.getElementById("CXcanvas");
const ctx = htmlcnv.getContext("2d"); //canvas context
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
function onEvent(e) {
    let reDR = false;
    console.log("Event-Type: " + e.type);
    for (let i = 0; i < viewelements.length; ++i) {
        if (viewelements[i].checkEvent(e)) {
            viewelements[i].handleEvent(e);
            reDR = true;
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
    for (let i = 0; i < viewelements.length; ++i) {
        viewelements[i].draw();
    }
}
function main() {
    initialize();
    let defaultview = new CXTablePlanView(ctx, 0, 0, 1, 1, true, true);
    viewelements.push(defaultview);
    defaultview.background_color = "#b3b3b3ff";
    drawCanvas();
}
