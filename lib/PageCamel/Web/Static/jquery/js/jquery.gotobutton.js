(function($){  
    $.fn.gotobutton = function(options) {
        var defaults = {
            //'icon':   'ui-icon-circle-arrow-e'
            'icon':   'ui-icon-trash'
        };
        
        options = $.extend({}, defaults, options);
        
        return this.each(function() {
            var obj = $(this);
            var dest = $(this).attr("goto");
            var marker = $('<span />').insertBefore($(this));
            
            var urlbutton = $('<img src="/pics/arrow.png">').insertAfter(marker);
            
            urlbutton.click(function() {
                window.location.assign(dest);
            });
            
            obj.remove();
            marker.remove();
            
        });  
    };  
})(jQuery);

