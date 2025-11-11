var logoutDialog;
var ttvars = new Object;
ttvars['trquote'] = new Object;
ttvars['json'] = new Object;

window.maskconfig = new Object;

// **** the standard BASE64 functions provided by JavaScript are total shit, since they don't handle
// **** UTF-8 encoding correctly. 
// **** Some very smart people on Stackoverflow worked out a solution, because Google and the Mozilla foundation
// **** don't seem to have the brains to provide a working update to their JavaScript engines.
// **** https://stackoverflow.com/questions/30106476/using-javascripts-atob-to-decode-base64-doesnt-properly-decode-utf-8-strings
function b64DecodeUnicode(str) {
    // Going backwards: from bytestream, to percent-encoding, to original string.
    return decodeURIComponent(atob(str).split('').map(function(c) {
        return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
    }).join(''));
}

function b64EncodeUnicode(str) {
    // first we use encodeURIComponent to get percent-encoded UTF-8,
    // then we convert the percent encodings into raw bytes which
    // can be fed into btoa.
    return btoa(encodeURIComponent(str).replace(/%([0-9A-F]{2})/g,
        function toSolidBytes(match, p1) {
            return String.fromCharCode('0x' + p1);
    }));
}

$(document).ready(function() {
    eventHandlerInitialization();

    // Load tt vars from master template
    loadTTVars('#mastertemplatedataset');
    loadTTVars('#masktemplatedataset');
    loadTTVars('#submasktemplatedataset');
    loadTTVars('#websocketmasktemplatedataset');
    loadTTVars('#autodialogstemplatedataset');

    if($('#maskconfigobject').length) {
        var confdata = $('#maskconfigobject').data('config');
        //console.log(confdata);
        window.maskconfig = JSON.parse(b64DecodeUnicode(confdata));
        //console.log(window.maskconfig);
    }

    if(ttvars.isdebugging == "1" && window.self === window.top) {
        // Only print this if we are in debug mode AND we are not running in an iframe (prevent duplicate prints from top and iframe)
        console.log("%c 🐞DEBUG MODE 🐞", "color:blue; font-size:50px");
    }

    console.log("PageCamel Version " + ttvars.pagecamelversion);

    $('#mobiledesktopselect_mobile').on('click', function() {
        document.cookie = "clientMode=mobile; path=/;";
        window.location.reload();
        //return false;
    });

    if(ttvars.enablepageviewstats == 1) {
        _init_pagecamel_pageviewstats();
    }

    // register all "pagecamelnavdestination onclick events
    $('[pagecamelnavdestination]').each(function() {
        var mndest = $(this).attr('pagecamelnavdestination');
        $(this).on('click', function() {
            if(window.NavigationClickHandler) {
                //NavigationClickHandler(mndest);
                return false;
            }
            location.href=mndest;
        });
    });

    $("select[searchable!='1']").selectmenu({
        width: 400
    });
    $("select[searchable='1']").each(function() {
        $(this).width(400);
        var extendable = false;
        if($(this).attr('extendable') == '1') {
            extendable = true;
        }
        if($(this).attr('customformat') == '1' && window.customSelect2Format) {
            $(this).select2({
               tags: extendable,
               templateResult: customSelect2Format
            });
        } else {
            $(this).select2({
               tags: extendable
            });
        }
        if(ttvars.touchinputenabled == "1") {
            $(this).on('select2:open', function (e) {
                var searchInput = $('.select2-search__field');

                addKeyboard(searchInput);
            });
        }
    });

    $("input[type=checkbox]").checkify({
        image_checked:'/pics/checkbox_classic_ON.png',
        image_unchecked:'/pics/checkbox_classic_OFF.png',
        image_checked_delete:'/pics/checkbox_classic_DELETE.png'
    });

    $("input[displaytype=dateandtime]").datetimepicker({
        format: 'Y-m-d H:i:s',
        mask:true,
    });

    $("input[displaytype=dateonly]").datepicker({
        dateFormat: 'yy-mm-dd',
        showOn: 'button',
        buttonImage: '/pics/calendar.png',
        buttonImageOnly: true,
        buttonText: ttvars.trquote.Calendarbutton
    });

    $("input[displaytype=monthonly]").datepicker({
        dateFormat: 'yy-mm',
        showOn: 'button',
        buttonImage: '/pics/calendar.png',
        buttonImageOnly: true,
        changeMonth: true,
        changeYear: true,
        showButtonPanel: true,
        buttonText: ttvars.trquote.Calendarbutton,
        onClose: function(dateText, inst) {
            var month = $("#ui-datepicker-div .ui-datepicker-month :selected").val();
            var year = $("#ui-datepicker-div .ui-datepicker-year :selected").val();
            $(this).val($.datepicker.formatDate('yy-mm', new Date(year, month, 1)));
        }
    });
    $("input[displaytype=monthonly]").on('focus', function () {
        $(".ui-datepicker-calendar").hide();
        $("#ui-datepicker-div").position({
            my: "center top",
            at: "center bottom",
            of: $(this)
        });
    });

    $("input[displaytype=yearonly]").datepicker({
        dateFormat: 'yy',
        showOn: 'button',
        buttonImage: '/pics/calendar.png',
        buttonImageOnly: true,
        changeMonth: false,
        changeYear: true,
        showButtonPanel: true,
        buttonText: ttvars.trquote.Calendarbutton,
        onClose: function(dateText, inst) {
            var year = $("#ui-datepicker-div .ui-datepicker-year :selected").val();
            $(this).val($.datepicker.formatDate('yy', new Date(year, 1, 1)));
        }
    });
    $("input[displaytype=yearonly]").on('focus', function () {
        $(".ui-datepicker-calendar").hide();
        $("#ui-datepicker-div").position({
            my: "center top",
            at: "center bottom",
            of: $(this)
        });
    });

    $("input[displaytype=timeonly]").timepicker({
        timeFormat: 'HH:mm',
        interval: 30,
        minTime: '00:00',
        maxTime: '23:30',
        startTime: '00:00',
        dynamic: false,
        dropdown: true,
        scrollbar: true
    });

    $("button, input:submit, input:reset, input:button").button();
    $("input.gotobutton[type=button]").gotobutton();

    $("span.cavacnote").cavacnote();

    if(window.extraOnLoadBeforeTables) {
        extraOnLoadBeforeTables();
    }

    $('#MainDataTable').statictable();
    $('#HelperTable1').statictable();
    $('#HelperTable2').statictable();
    $('#HelperTable3').statictable();
    $('#HelperTable4').statictable();
    $('#HelperTable5').statictable();
    $('#HelperTable6').statictable();
    $('#HelperTable7').statictable();
    $('#HelperTable8').statictable();
    $('#HelperTable9').statictable();
    $('#HelperTable10').statictable();
    $('#HelperTable11').statictable();
    $('#SubHelperTable1').statictable();

    $("table[statictable='1']").each(function() {
        //console.log("Turn to static table:");
        //console.log($(this));
        $(this).statictable();
    });


    filter_table = $('#MainFilterTable').dataTable({
                "pagingType": "simple",
                "stateSave": true, // Save state but we will override the SORTING later
                "lengthMenu": [[5, 10, 25, 50, -1], [5, 10, 25, 50, ttvars.trquote.All]],
                "language": {
                    "lengthMenu": ttvars.trquote.Countperpage,
                    "zeroRecords": ttvars.trquote.Nomatches,
                    "info": ttvars.trquote.Recordcount,
                    "infoEmpty": ttvars.trquote.Norecords,
                    "infoFiltered": ttvars.trquote.Maxrecords,
                    "first": ttvars.trquote.First,
                    "last": ttvars.trquote.Last,
                    "paginate": {
                        "next": "<span class='ui-icon ui-icon-circle-arrow-e'>",
                        "previous": "<span class='ui-icon ui-icon-circle-arrow-w'>"
                    },
                    "search": ttvars.trquote.Filterresults,
                    "processing": '<img src="/pics/loading_bar.gif' + ttvars.urlreloadpostfix + '">'
                },
                "ordering": [],
                "jQueryUI": true,
                "autoWidth": false
            });

    $('#MainFilterDisplayTable').dataTable({
                "pagingType": "simple",
                "stateSave": true, // Save state but we will override the SORTING later
                //"sPaginationType": "full_numbers",
                "lengthMenu": [[5, 10, 25, 50, -1], [5, 10, 25, 50, ttvars.trquote.All]],
                "language": {
                    "lengthMenu": ttvars.trquote.Countperpage,
                    "zeroRecords": ttvars.trquote.Nomatches,
                    "info": ttvars.trquote.Recordcount,
                    "infoEmpty": ttvars.trquote.Norecords,
                    "infoFiltered": ttvars.trquote.Maxrecords,
                    "first": ttvars.trquote.First,
                    "last": ttvars.trquote.Last,
                    "paginate": {
                        "next": "<span class='ui-icon ui-icon-circle-arrow-e'>",
                        "previous": "<span class='ui-icon ui-icon-circle-arrow-w'>"
                    },
                    "search": ttvars.trquote.Filterresults
                },
                "ordering": [],
                "jQueryUI": true,
                "autoWidth": false
            });


    if(filter_table) {
        // change back to native server side sorting
        filter_table.fnSortNeutral();

        // Add special submit function to hide the table and restore hidden rows
        $('#MainFilterForm').on('submit', function(){
            try {
                setVisibility('pagecamelMenuContent', false);
                setVisibility('pagecamelPageContent', false);
                setVisibility('pagecamelFooterContent', false);
                setVisibility('pagecamelSendingContent', true);
            } catch(err) {
                console.log(err);
            }

            $(filter_table.fnGetHiddenNodes()).appendTo(this);

            return true;
        });
    }

    $( "#menutabs, #submenutabs" ).buttonset();

    $("a[activemenutab='1']").each(function() {
        $(this).addClass('ui-state-active');
        $(this).on('mouseleave',function() {
            $(this).addClass('ui-state-active');
        });
    });

    $( "#dialog-logout" ).dialog({
        autoOpen: false,
        resizable: false,
        modal: true,
        width: 400,
        height: 600,
        buttons: [
            {
                text: ttvars.trquote.Logout,
                click: function() {
                    if(window.NavigationClickHandler) {
                        NavigationClickHandler('/user/logout');
                    } else {
                        location.href="/user/logout";
                    }
                }
            },
            {
                text: ttvars.trquote.Close,
                click: function() {
                    $( this ).dialog( "close" );
                }
            }
        ]
    });


    $( "#dialog-whoami" ).dialog({
        autoOpen: false,
        resizable: false,
        modal: true,
        width: 600,
        height: 350,
        buttons: [
            {
                text: ttvars.trquote.Close,
                click: function() {
                    $( this ).dialog( "close" );
                    return false;
                }
            }
        ]
    });

    $( "#dialog-versioninfo" ).dialog({
        autoOpen: false,
        resizable: false,
        modal: true,
        width: 600,
        height: 350,
        buttons: [
            {
                text: ttvars.trquote.Close,
                click: function() {
                    $( this ).dialog( "close" );
                    return false;
                }
            }
        ]
    });

    if(ttvars.isaprilfoolsday == "1") {
        $( "#dialog-aprilfool" ).dialog({
            autoOpen: false,
            resizable: false,
            modal: true,
            width: 600,
            height: 350,
            buttons: [
                {
                    text: ttvars.trquote.Close,
                    click: function() {
                        $( this ).dialog( "close" );
                        return false;
                    }
                }
            ]
        });
    }

    // AutoDialogs
    if(window.JSinitTTDialogs) {
        JSinitTTDialogs();
    }

    try {
        setVisibility('pagecamelMenuContent', true);
        setVisibility('pagecamelPageContent', true);
        setVisibility('pagecamelFooterContent', true);
        setVisibility('pagecamelLoadingContent', false);
    } catch(err) {
        console.log(err);
    }


    $('#sidebar_menu').menu();

    $('#top_menu').menu();
      
    $('#top_menu').menu({
        position: { my: 'left top', at: 'left bottom' },
        blur: function() {
            $(this).menu('option', 'position', { my: 'left top', at: 'left bottom' });
        },
        focus: function(e, ui) {
            if ($('#top_menu').get(0) !== $(ui).get(0).item.parent().get(0)) {
                $(this).menu('option', 'position', { my: 'left top', at: 'right top' });
            }
        },
    });



    // If appropriate, start the computer map
    if(window.startMap) {
        startMap();
    }

    if(window.extraOnLoad) {
        extraOnLoad();
    }

    $( "#tabs" ).tabs();

    if(ttvars.webappshoweyes == "1") {
        $('.iris').xeyes();

        function blinkeyeClose() {
            $('.eye').css('background-color', '#000000');
            window.setTimeout(blinkeyeOpen, 150);
        }
        function blinkeyeOpen() {
            $('.eye').css('background-color', '#FFFFFF');
            window.setTimeout(blinkeyeClose, 14000);
        }
        window.setTimeout(blinkeyeClose, 10000);
    }

    if(window.lateExtraOnLoad) {
        lateExtraOnLoad();
    }

    if(ttvars.pagetitle != "Login" && ttvars.pagetitle != "Logout" && ttvars.pagetitle != "Reset Password" && ttvars.ispublicurl != "1") {
        startSessionRefresh('lastsessionrefresh', '/user/sessionrefresh');
    }

    if(ttvars.webappshowsanta == "1") {
        $('#santa').sprite({fps: 8, no_of_frames: 8}).spState(1);
        $('#santa').animate({
            left: "50px"
        }, 12000);
    }

    if(ttvars.webappusemousetrail == "1") {
        $(document.body).cursorTrail({
            "class": "cursor-trail-color"
        });
    }

    if(ttvars.animatedprojectlogo == "1") {
        projectlogoInit();
    }

    if(ttvars.setdocumenthref !== "") {
        document.location.href = ttvars.setdocumenthref;
    }

    if(ttvars.focusonfield !== "") {
        $(ttvars.focusonfield).focus();
    }

    // Fix button fonts
    $('.ui-button').each(function() {
        $(this).css('font-family', ttvars.fontface);
    });

    if(ttvars.keyfoblogout == "1" && ttvars.keyfobsoftlogout != "1") {
        setInterval(runFobLogoutReader, 100);
    }

    if(ttvars.enabledb == "1") {
        pagecamelDBInit();
    }

    $('input[type="text"],input[type="search"],textarea').each(function() {
        var displaytype = $(this).attr("displaytype");

        var isdatefield = false;
        if(displaytype === "dateonly" || displaytype === "monthonly" || displaytype === "yearonly") {
            isdatefield = true;
        }

        if(ttvars.touchinputenabled == "1" && !isdatefield) {
            addKeyboard($(this));
            return;
        }

        if(!isdatefield) {
            return;
        }

        // VALIGNing the text field in regards to the icons requires us to make a sub table and re-parent the elements into it

        var calimg = '/pics/calendar.png';
        var clrimg = '/pics/clearfield.png';
        var rstimg = '/pics/resetfield.png';
        if(ttvars.touchinputenabled == "1") {
            calimg = '/pics/calendar_large.png';
            clrimg = '/pics/clearfield_large.png';
            rstimg = '/pics/resetfield_large.png';
        }

        // Create a HTML table on the fly
        // We dont give IDs to the TDs, but use temporary divs instead. This makes sure we don't have clashing IDs if there are multiple date fields in one mask
        var htmltable = '<table><tr valign="center"><td><div id="calplaceholder1"></div></td><td><div id="calplaceholder2"></div></td><td><div id="calplaceholder3"></div></td><td><div id="calplaceholder4"></div></td></tr></table>';
        $(this).parent().append(htmltable);

        // Find the td elements (parents of the divs)
        var ph1 = $('#calplaceholder1').parent();
        var ph2 = $('#calplaceholder2').parent();
        var ph3 = $('#calplaceholder3').parent();
        var ph4 = $('#calplaceholder4').parent();

        // Remove the divs
        $('#calplaceholder1').remove();
        $('#calplaceholder2').remove();
        $('#calplaceholder3').remove();
        $('#calplaceholder4').remove();

        // Find the calendar icon
        var calbtn = $(this).next();

        // Move the text field to the first TD
        $(this).appendTo(ph1);
        var mainid = $(this).attr('id');

        // Remember the original value
        var origval = $(this).val();
        $(this).attr('origval', origval);

        // Move the calendar icon into the second and replace the image src
        calbtn.appendTo(ph2);
        calbtn.attr('src', calimg);

        // Create the "reset field" icon in the third td
        var resetid = mainid + '_rst';
        var resethtml = '<img src="' + rstimg + '" id="' + resetid + '" parentid="' + mainid + '">';
        ph3.append(resethtml);
        $('#' + resetid).on('click', function() {
            var parentid = '#' + $(this).attr('parentid');
            var origval = $(parentid).attr('origval');
            $(parentid).val(origval);
            $(parentid).trigger('change');
        });

        // Create the "clear field" icon in the fourth td
        var clearid = mainid + '_clr';
        var clearhtml = '<img src="' + clrimg + '" id="' + clearid + '" parentid="' + mainid + '">';
        ph4.append(clearhtml);
        $('#' + clearid).on('click', function() {
            var parentid = '#' + $(this).attr('parentid');
            $(parentid).val('');
            $(parentid).trigger('change');
        });
    });

    if(window.defaultlayoutExtraOnLoad) {
        defaultlayoutExtraOnLoad();
    }

    // Always reload the page if it comes out of "suspend" from bfcache (terrible chrome feature)
    // See https://web.dev/articles/bfcache
    window.addEventListener('pageshow', (event) => {
        if(event.persisted) {
            window.location.reload();
        }
    });

});

function onAppReactivate() {
    console.log("*************** onAppReactivate() called by APP ******");
    if(window.wsOnAppReactivate) {
        window.wsOnAppReactivate();
    }
}

function setVisibility(name, visible) {
    if(visible) {
        $('#' + name).show();
    } else {
        $('#' + name).hide();
    }
}


var foblogoutreader = new XMLHttpRequest();
var foblogoutrunning = 0;
var foblogoutrequestactive = 0;
function runFobLogoutReader() {
    if(foblogoutrunning == 1 || foblogoutrequestactive == 1) {
        return;
    }
    foblogoutreader.open("GET", '/user/fobreader', true);
    foblogoutreader.onreadystatechange=function() {
        if(foblogoutreader.readyState == 4) {
            //console.log("REQUEST STATUS: " + foblogoutreader.status);
            foblogoutrequestactive = 0;
            if(foblogoutreader.status != 200) {
                //console.log("REQUEST FAILED");
                return;
            }
            var newfob = foblogoutreader.responseText;
            //console.log(newfob + ' # ' + ttvars.keyfobid);
            if(newfob != ttvars.keyfobid) {
                //console.log("Starting FOB logout...");
                foblogoutrunning = 1;
                $.blockUI({ message: '<h1>' + ttvars.trquote.Keyfoblogout + '<br/><img src="/pics/loading_bar_large.gif' + ttvars.urlreloadpostfix + '" /></h1>' });
                location.href="/user/logout";
            }
        }
    }
    //console.log("FOB REQUEST STARTED");
    foblogoutrequestactive = 1;
    foblogoutreader.send(null);
}


function addKeyboard(elem) {
    //------------------------------------------ ON SCREEN KEYBOARD --------------------------------------------
    var keyboardConfig = {

          // set this to ISO 639-1 language code to override language set by the layout
          // http://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
          // language defaults to "en" if not found
          language     : 'en',
          rtl          : false, // language direction right-to-left

          // *** choose layout ***
          layout       : 'german-qwertz-1',
          //customLayout : { 'normal': ['{cancel}'] },
          usePreview: false,
          css : {
                // input & preview
                //input          : 'ui-widget-content ui-corner-all',
                input          : '',
                // keyboard container
                container      : 'ui-widget-content ui-widget ui-corner-all ui-helper-clearfix',
                // keyboard container extra class (same as container, but separate)
                popup: '',
                // default state
                buttonDefault  : 'ui-state-default ui-corner-all',
                // hovered button
                buttonHover    : 'ui-state-hover',
                // Action keys (e.g. Accept, Cancel, Tab, etc); this replaces the "actionClass" option
                buttonAction   : 'ui-state-active',
                // Active keys (e.g. shift down, meta keyset active, combo keys active)
                buttonActive   : 'ui-state-active',
                // used when disabling the decimal button {dec}
                buttonDisabled : 'ui-state-disabled',
                // empty button class name {empty}
                buttonEmpty    : 'ui-keyboard-empty'
          },
          autoAccept : true,
          reposition: true,
          change: function(e, keyboard, el) {
                var keys = {
                    bksp: 8,
                    tab: 9,
                    enter: 13,
                    space: 32,
                    delete: 46
                };

                var key = (keyboard.last.key || '').toLowerCase();
                // trigger a keydown for "special" keys
                e.type = keys[key] ? 'keydown' : 'input';
                e.which = keys[key] || key.charCodeAt(0);
                keyboard.$el.trigger(e);
        },
        position: {
            // Position at bottom of screen
            of: window,
            my: 'bottom center',
            at: 'bottom center',
            // used when "usePreview" is false
            at2: 'bottom center'
        }
    };

    // Prevent native keyboard from appearing
    elem.attr('readonly', 'readonly');
    elem.on('focus', function() {
        $(this).attr('readonly', 'readonly');
    });

    elem.keyboard(keyboardConfig).addTyping({
            showTyping: true,
            delay: 50
    });

    // Force keyboard to bottom after it appears
    var positionKeyboard = function() {
        var $keyboard = $('.ui-keyboard');
        if($keyboard.is(':visible')) {
            $keyboard.css({
                'position': 'fixed',
                'bottom': '0',
                'left': '50%',
                'transform': 'translateX(-50%) scale(1.2)',
                'top': 'auto',
                'width': '100%',
                'max-width': '100vw',
                'transform-origin': 'bottom center'
            });

            // Resize buttons for better touch experience
            $keyboard.find('button').css({
                'font-size': '1.26em',
                'min-height': '60px',
                'padding': '15px'
            });
        }
    };

    elem.on('visible.keyboard', positionKeyboard);

    // Reposition on orientation change and window resize
    $(window).on('orientationchange resize', function() {
        setTimeout(positionKeyboard, 100);
    });
}
function ShowAprilFools() {
    document.getElementById('alientransmission').play();
    $( "#dialog-aprilfool" ).dialog("open");
}


function CheckLogout() {
    if(ttvars.isaprilfoolsday == "1") {
        document.getElementById('alientransmission').play();
    }
    $( "#dialog-logout" ).dialog("open");

}

function showWhoami() {
    if(ttvars.isaprilfoolsday == "1") {
        document.getElementById('alientransmission').play();
    }
    $( "#dialog-whoami" ).dialog("open");
    return false;
}

function showVersionInfoDialog() {
    if(ttvars.isaprilfoolsday == "1") {
        document.getElementById('alientransmission').play();
    }
    $( "#dialog-versioninfo" ).dialog("open");
    return false;
}


function pagecamelDBInit() {
    //console.log("pagecamelDBInit called **************************************");

    window.sqlite.initialize.then(()=>{
        if(window.pcws) {
            window.pcws.initializeSQL(window.sqlite);
        }
    }).catch((msg)=>{console.error("Error at SQL initialisation: " + msg)});
}

