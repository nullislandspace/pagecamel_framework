import { CXTextInput } from "./src/mycxelements/cxtextinput.js";
import { CXButton } from "./src/mycxelements/cxbutton.js";
import { CXScrollList } from "./src/mycxelements/cxscrolllist.js";
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
let viewelements = [];
let htmlcanvas = `<canvas id='CXcanvas' style='background-color: #b3b3b3ff; '></canvas>`;
document.body.innerHTML = htmlcanvas;
const htmlcnv = document.getElementById("CXcanvas");
const ctx = htmlcnv.getContext("2d");
export function bodyOnLoad() {
    main();
    return true;
}
function initialize() {
    window.addEventListener('resize', resizeCanvas, false);
    htmlcnv.addEventListener('click', onEvent, false);
    htmlcnv.addEventListener('mousedown', onEvent, false);
    htmlcnv.addEventListener('mousemove', onEvent, false);
    htmlcnv.addEventListener('mouseup', onEvent, false);
    htmlcnv.addEventListener('mouseleave', onEvent, false);
    document.addEventListener('keydown', onEvent, false);
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
function drawCanvas() {
    for (let i = 0; i < viewelements.length; ++i) {
        viewelements[i].draw();
    }
}
function main() {
    initialize();
    let textinput = new CXTextInput(ctx, 0.1, 0.1, 0.2, 0.05, true, true);
    textinput.border_width = 0.05;
    let button = new CXButton(ctx, 0.1, 0.2, 0.2, 0.05, true, true);
    button.text = "Button";
    button.gradient = ['#ff0000ff', '#00ff00ff'];
    button.radius = 0.05;
    let scrolllist = new CXScrollList(ctx, 0.1, 0.3, 0.7, 0.6, true, true);
    let data = [];
    for (let i = 0; i < 100; ++i) {
        let row = [];
        for (let j = 0; j < 3; ++j) {
            row.push("Row " + i.toString() + " Col " + j.toString());
        }
        data.push(row);
    }
    scrolllist.list = data;
    viewelements.push(scrolllist);
    viewelements.push(button);
    viewelements.push(textinput);
    drawCanvas();
}
