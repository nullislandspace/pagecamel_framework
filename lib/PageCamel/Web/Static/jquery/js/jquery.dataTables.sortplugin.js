// *** FILESIZE ***
jQuery.fn.dataTableExt.oSort['file-size-asc']  = function(a,b) {
    var x = a.substring(0,a.length - 2);
    var y = b.substring(0,b.length - 2);
       
    var x_unit = (a.substring(a.length - 2, a.length) == "MB" ? 1000 : (a.substring(a.length - 2, a.length) == "GB" ? 1000000 : 1));
    var y_unit = (b.substring(b.length - 2, b.length) == "MB" ? 1000 : (b.substring(b.length - 2, b.length) == "GB" ? 1000000 : 1));
    
    x = parseInt( x * x_unit );
    y = parseInt( y * y_unit );
    
    return ((x < y) ? -1 : ((x > y) ?  1 : 0));
};

jQuery.fn.dataTableExt.oSort['file-size-desc'] = function(a,b) {
    var x = a.substring(0,a.length - 2);
    var y = b.substring(0,b.length - 2);

    var x_unit = (a.substring(a.length - 2, a.length) == "MB" ? 1000 : (a.substring(a.length - 2, a.length) == "GB" ? 1000000 : 1));
    var y_unit = (b.substring(b.length - 2, b.length) == "MB" ? 1000 : (b.substring(b.length - 2, b.length) == "GB" ? 1000000 : 1));

    x = parseInt( x * x_unit);
    y = parseInt( y * y_unit);

    return ((x < y) ?  1 : ((x > y) ? -1 : 0));
};

jQuery.fn.dataTableExt.aTypes.unshift(
    function ( sData )
    {
        var sValidChars = "0123456789";
        var Char;

        /* Check the numeric part */
        for ( i=0 ; i<(sData.length - 3) ; i++ )
        {
            Char = sData.charAt(i);
            if (sValidChars.indexOf(Char) == -1)
            {
                return null;
            }
        }

        /* Check for size unit KB, MB or GB */
        if ( sData.substring(sData.length - 2, sData.length) == "KB"
            || sData.substring(sData.length - 2, sData.length) == "MB"
            || sData.substring(sData.length - 2, sData.length) == "GB" )
        {
            return 'file-size';
        }
        return null;
    }
);


// *** NUMBERS WITH HTML ***
jQuery.fn.dataTableExt.oSort['num-html-asc']  = function(a,b) {
    var x = a.replace( /<.*?>/g, "" );
    var y = b.replace( /<.*?>/g, "" );
    x = parseFloat( x );
    y = parseFloat( y );
    return ((x < y) ? -1 : ((x > y) ?  1 : 0));
};

jQuery.fn.dataTableExt.oSort['num-html-desc'] = function(a,b) {
    var x = a.replace( /<.*?>/g, "" );
    var y = b.replace( /<.*?>/g, "" );
    x = parseFloat( x );
    y = parseFloat( y );
    return ((x < y) ?  1 : ((x > y) ? -1 : 0));
};

jQuery.fn.dataTableExt.aTypes.unshift( function ( sData )
{
    sData = typeof sData.replace == 'function' ?
        sData.replace( /<.*?>/g, "" ) : sData;
    sData = $.trim(sData);
    
    var sValidFirstChars = "0123456789-";
    var sValidChars = "0123456789.";
    var Char;
    var bDecimal = false;
    
    /* Check for a valid first char (no period and allow negatives) */
    Char = sData.charAt(0); 
    if (sValidFirstChars.indexOf(Char) == -1) 
    {
        return null;
    }
    
    /* Check all the other characters are valid */
    for ( var i=1 ; i<sData.length ; i++ ) 
    {
        Char = sData.charAt(i); 
        if (sValidChars.indexOf(Char) == -1) 
        {
            return null;
        }
        
        /* Only allowed one decimal place... */
        if ( Char == "." )
        {
            if ( bDecimal )
            {
                return null;
            }
            bDecimal = true;
        }
    }
    
    return 'num-html';
} );

// *** IP ADDRESS ***
jQuery.fn.dataTableExt.oSort['ip-address-asc']  = function(a,b) {
    var m = a.split("."), x = "";
    var n = b.split("."), y = "";
    for(var i = 0; i < m.length; i++) {
        var item = m[i];
        if(item.length == 1) {
            x += "00" + item;
        } else if(item.length == 2) {
            x += "0" + item;
        } else {
            x += item;
        }
    }
    for(var i = 0; i < n.length; i++) {
        var item = n[i];
        if(item.length == 1) {
            y += "00" + item;
        } else if(item.length == 2) {
            y += "0" + item;
        } else {
            y += item;
        }
    }
    return ((x < y) ? -1 : ((x > y) ? 1 : 0));
};

jQuery.fn.dataTableExt.oSort['ip-address-desc']  = function(a,b) {
    var m = a.split("."), x = "";
    var n = b.split("."), y = "";
    for(var i = 0; i < m.length; i++) {
        var item = m[i];
        if(item.length == 1) {
            x += "00" + item;
        } else if (item.length == 2) {
            x += "0" + item;
        } else {
            x += item;
        }
    }
    for(var i = 0; i < n.length; i++) {
        var item = n[i];
        if(item.length == 1) {
            y += "00" + item;
        } else if (item.length == 2) {
            y += "0" + item;
        } else {
            y += item;
        }
    }
    return ((x < y) ? 1 : ((x > y) ? -1 : 0));
};

jQuery.fn.dataTableExt.aTypes.unshift(
    function ( sData )
    {
        if (/^\d{1,3}[\.]\d{1,3}[\.]\d{1,3}[\.]\d{1,3}$/.test(sData)) {
            return 'ip-address';
        }
        return null;
    }
);
