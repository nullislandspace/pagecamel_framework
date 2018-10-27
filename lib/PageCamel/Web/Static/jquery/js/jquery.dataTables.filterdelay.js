jQuery.fn.dataTableExt.oApi.fnSetFilteringDelay = function ( oSettings, iDelay ) {
    var _that = this;
 
    if ( iDelay === undefined ) {
        iDelay = 250;
    }
      
    this.each( function ( i ) {
        $.fn.dataTableExt.iApiIndex = i;
        var
            $this = this,
            oTimerId = null,
            sPreviousSearch = "",
            sNewSearch = null,
            anControl = $( 'input', _that.fnSettings().aanFeatures.f );
          
            anControl.unbind( 'keyup' ).bind( 'keyup', function() {
            var $$this = $this;

            sNewSearch = $.trim(anControl.val());
            if (sPreviousSearch === null || sPreviousSearch != sNewSearch || sNewSearch === "") {
                _that.fnProcessingIndicator();
                window.clearTimeout(oTimerId);
                sPreviousSearch = $.trim(anControl.val()); 
                oTimerId = window.setTimeout(function() {
                    $.fn.dataTableExt.iApiIndex = i;
                    _that.fnFilter( anControl.val() );
                }, iDelay);
            }
        });
          
        return this;
    } );
    return this;
};
