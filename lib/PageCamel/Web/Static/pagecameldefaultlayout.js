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

$(document).ready(function(){
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

    if(ttvars.isdebugging == "1") {
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
        buttonImage: '/pics/calendar.gif',
        buttonImageOnly: true,
        buttonText: ttvars.trquote.Calendarbutton
    });

    $("input[displaytype=monthonly]").datepicker({
        dateFormat: 'yy-mm',
        showOn: 'button',
        buttonImage: '/pics/calendar.gif',
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
        buttonImage: '/pics/calendar.gif',
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

    if(ttvars.touchinputenabled == "1") {
        $('input[type="text"],input[type="search"],textarea').each(function() {
            var displaytype = $(this).attr("displaytype");
            if(displaytype === "dateonly" || displaytype === "monthonly" || displaytype === "yearonly" || displaytype === "timeonly") {
                // No keyboard
                // TODO: Generalize with a specific setting on the field like "disablekeyboard=1" or something
                console.log("Onscreen keyboard disabled for" + $(this).attr('name'));
                $(this).next().attr('src', '/pics/calendar_large.gif');
                $(this).parent().attr('valign', 'top');

            } else {
                addKeyboard($(this));
            }
        });
    }

    if(window.defaultlayoutExtraOnLoad) {
        defaultlayoutExtraOnLoad();
    }

});

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
    elem.keyboard({

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
          autoAccept : true 
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

