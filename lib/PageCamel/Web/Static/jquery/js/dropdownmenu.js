var jsddm_closetimer = 0;
var jsddm_timeout         = 500;
var jsddm_ddmenuitem      = 0;
function jsddm_open()
{	jsddm_canceltimer();
	jsddm_close();
	jsddm_ddmenuitem = $(this).find('ul').eq(0).css('visibility', 'visible');}

function jsddm_close()
{	if(jsddm_ddmenuitem) jsddm_ddmenuitem.css('visibility', 'hidden');}

function jsddm_timer()
{	jsddm_closetimer = window.setTimeout(jsddm_close, jsddm_timeout);}

function jsddm_canceltimer()
{	if(jsddm_closetimer)
	{	window.clearTimeout(jsddm_closetimer);
		jsddm_closetimer = null;}}
