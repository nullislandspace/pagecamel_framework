import { CXDropDown } from "./src/mycxelements/cxdropdown.js";
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
    ctx.clearRect(0, 0, htmlcnv.width, htmlcnv.height);
    ctx.fillStyle = "#b3b3b3ff";
    ctx.fillRect(0, 0, htmlcnv.width, htmlcnv.height);
    for (let i = 0; i < viewelements.length; ++i) {
        viewelements[i].draw();
    }
}
function main() {
    initialize();
    let dropdown = new CXDropDown(ctx, 0.8, 0.5, 0.15, 0.2, true, false);
    dropdown.text = 'Name';
    dropdown.field_width = 0.8;
    dropdown.field_height = 0.2;
    dropdown.list = [['Test 1'], ['Test 2'], ['Test 3'], ['Test 4'], ['Test 5'], ['Test 6'], ['Test 7'], ['Test 8'], ['Test 9'], ['Test 10'], ['Test 11'], ['Test 12'], ['Test 13'], ['Test 14'], ['Test 15']];
    dropdown.background_color = '#ff0000';
    viewelements.push(dropdown);
    drawCanvas();
}
