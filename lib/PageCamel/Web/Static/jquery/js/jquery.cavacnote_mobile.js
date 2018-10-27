var jquery_cavacnote_mobile_count = 0;

(function($){  
    $.fn.cavacnote_mobile = function(options) {
        
        return this.each(function() {
            var obj = $(this);
            var popuptitle = $(this).attr("popuptitle");
            var popuptext = $(this).attr("popuptext");
            popuptext = popuptext.replace(/#BR#/gm," "); // don't use line breaks in mobile
            
            //console.log("Creating Popup for " + popuptitle + " ### " + popuptext);
            
            var dialogid = 'cavacnote' + jquery_cavacnote_count;
            jquery_cavacnote_count = jquery_cavacnote_count + 1;
            
            //$("<div id='" + dialogid + "' title='" + popuptitle + "'><p>" + popuptext + "</p></div>").insertAfter(obj);
            $("<div id='" + dialogid + "' data-role='popup'><p><b>" + popuptitle + "</b></p><p>" + popuptext + "</p></div>").insertAfter(obj);
            $('#' + dialogid).popup({
                history: false
            });
            
            $(obj).click(function() {
                //console.log("Opening popup " + dialogid);
                $('#' + dialogid).popup('open');
                return false;
            });

        });  
    };  
})(jQuery);

