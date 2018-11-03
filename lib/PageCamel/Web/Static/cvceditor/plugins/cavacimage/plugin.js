CVCEDITOR.plugins.add('cavacimage', {
    icons: 'cavacimage',
    init: function(editor) {
        editor.addCommand('cavacimage', new CVCEDITOR.dialogCommand('cavacImageDialog'), {
            allowedContent: 'img[class,src,width,height,border,hovertext]'
        });
        editor.ui.addButton('cavacimage', {
            label: 'Cavac Image',
            command: 'cavacimage',
            toolbar: 'insert'
        });
        CVCEDITOR.dialog.add( 'cavacImageDialog', this.path + 'dialogs/cavacimage.js' );
        
        // Context menu for editing existing notes
        if(editor.contextMenu) {
            editor.addMenuGroup('cavacGroup');
            editor.addMenuItem('cavacimageItem', {
                label: "Edit Cavac Image",
                icon: this.path + 'icons/cavacimage.png',
                command: 'cavacimage',
                group: 'cavacGroup'
            });
            
            editor.contextMenu.addListener( function(element) {
                var isCavacImage = (element.is( 'img' ) && (element.hasClass('cavacimage')))
                    || (element.hasAscendant( 'img' ) && element.getAscendant('span').hasClass('cavacimage'));
                if(isCavacImage) {
                    return { cavacimageItem: CVCEDITOR.TRISTATE_OFF};
                }
                
            });
        }
    }
});
