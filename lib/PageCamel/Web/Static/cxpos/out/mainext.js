import * as cxv from './cxviews/cxviews.js';
let htmlppidiv = `<div id='testdiv' style='height: 1in; left: -100%; position: absolute; top: -100%; width: 1in;'></div>`;
document.body.innerHTML = htmlppidiv;
let devicePixelRatio = window.devicePixelRatio || 1;
let dpi_x = document.getElementById('testdiv').offsetWidth * devicePixelRatio;
let dpi_y = document.getElementById('testdiv').offsetHeight * devicePixelRatio;
const min_dpi = 96;
const min_width = 1024;
const min_height = 768;
let viewelements = [];
let htmlcanvas = `<canvas id='CXcanvas' style='background-color: #b3b3b3ff; '></canvas>`;
document.body.innerHTML = htmlcanvas;
const htmlcnv = document.getElementById("CXcanvas");
const ctx = htmlcnv.getContext("2d");
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
export function mainext() {
    initialize();
    let tableplan = new cxv.CXTablePlanView(ctx);
    viewelements.push(tableplan);
    drawCanvas();
}
//# sourceMappingURL=mainext.js.map