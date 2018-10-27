var jquery_checkify_count = 0;

function checkifyInvertAll (colname) {
    if(colname == null) {
        colname = 'Default';
    }
    $('.CheckifyButtonSelectorClass' + colname).trigger('click');
    return false;
}

(function($){  
    $.fn.checkify = function(options) {
        var defaults = {
            'image_checked':   '/pics/checkbox_classic_ON.png',
            'image_unchecked': '/pics/checkbox_classic_OFF.png',
            'image_checked_delete': '/pics/checkbox_classic_DELETE.png'
        };
        
        options = $.extend({}, defaults, options);
        
        return this.each(function() {
            var obj = $(this);

            var noCheckify = $(this).hasClass('nocheckify');
            if(noCheckify) {
                return;
            }

            var marker = $('<span />').insertBefore($(this));
            var checked = $(this).is(':checked');
            var isDelete = $(this).hasClass('delete');
            var cname = $(this).attr("name");
            var cinputid = "checkify_input_" + jquery_checkify_count + "_" + cname;
            var cimageid = "checkify_image_" + jquery_checkify_count + "_" + cname;

            
            jquery_checkify_count = jquery_checkify_count + 1;
            
    
            var cbutton;

            var realval = $(this).attr("realvalue");
            if(realval == null) {
                realval = 'on';
            }
            var curval = realval;
            if(!checked) {
                curval = '';
            }
            var inputclass = "";
            if(isDelete) {
                inputclass="delete";
            }
            var columnName = $(this).attr("colname");
            if(columnName == null) {
                columnName = 'Default';
            }
            
            // The callback should only be the function name!
            var callback = $(this).attr("callback");
            if(callback == null) {
                callback = '';
            }
            
            $(this).remove();
            $('<input type="hidden" name="' + cname + '" value="' + curval + '" id="' + cinputid + '" realvalue="' + realval + '" class="' + inputclass + '" callback="' + callback + '" >').insertAfter(marker);
            
            var curimg = options.image_unchecked;
            if(checked) {
                if(isDelete) {
                    curimg = options.image_checked_delete;
                } else {
                    curimg = options.image_checked;
                }
            }
    
            cbutton = $('<img src="' + curimg + '" id="' + cimageid + '" alt="' + cinputid + '" class="CheckifyButtonSelectorClass' + columnName + '">').insertAfter(marker);

            $(cbutton).click(function() {
                var state = $("#" + cinputid).val();
                var newval = '';
                if(state != "") {
                    $("#" + cinputid).val("");
                    $("#" + cimageid).attr("src", options.image_unchecked);
                } else {
                    var realval = $("#" + cinputid).attr("realvalue");
                    if(realval != null) {
                        $("#" + cinputid).val(realval);
                        newval = realval;
                    } else {
                        $("#" + cinputid).val("on");
                        newval = 'on';
                    }
                    if($("#" + cinputid).hasClass('delete')) {
                        $("#" + cimageid).attr("src", options.image_checked_delete);
                    } else {
                        $("#" + cimageid).attr("src", options.image_checked);
                    }
                    
                }
                
                // Run the callback function if possible
                var callback = $("#" + cinputid).attr("callback");
                if(callback != '') {
                    var fn = window[callback];
                    
                    if(typeof fn === 'function') {
                        fn(newval);
                    }
                }                
                
            });

            marker.remove();
        });  
    };  
})(jQuery);

