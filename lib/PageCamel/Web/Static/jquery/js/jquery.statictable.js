(function($){  
    $.fn.statictable = function(options) {
        
        return this.each(function() {
            var obj = $(this);

            obj.find('tbody').find('tr:even').addClass('staticeven');
            obj.find('tbody').find('tr:odd').addClass('staticodd');
            obj.find('thead').find('th').addClass('statichead');

        });  
    };  
})(jQuery);

