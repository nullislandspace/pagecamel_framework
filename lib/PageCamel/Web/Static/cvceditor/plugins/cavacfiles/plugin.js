CKEDITOR.plugins.add('cavacfiles', {
    icons: 'cavacfiles',
    init: function(editor) {
        editor.addCommand('cavacfiles', new CKEDITOR.dialogCommand('cavacFilesDialog'), {
            allowedContent: 'a[class,href,alt,title,bytesize,humansize]'
        });
        editor.ui.addButton('cavacfiles', {
            label: 'Cavac Files',
            command: 'cavacfiles',
            toolbar: 'insert'
        });
        CKEDITOR.dialog.add( 'cavacFilesDialog', this.path + 'dialogs/cavacfiles.js' );
        
        // Context menu for editing existing notes
        if(editor.contextMenu) {
            editor.addMenuGroup('cavacGroup');
            editor.addMenuItem('cavacfilesItem', {
                label: "Edit Cavac Files",
                icon: this.path + 'icons/cavacfiles.png',
                command: 'cavacfiles',
                group: 'cavacGroup'
            });
            
            editor.contextMenu.addListener( function(element) {
                var isCavacFiles = (element.is( 'a' ) && (element.hasClass('cavacfiles')))
                    || (element.hasAscendant( 'a' ) && element.getAscendant('a').hasClass('cavacfiles'));
                if(isCavacFiles) {
                    return { cavacfilesItem: CKEDITOR.TRISTATE_OFF};
                }
                
            });
        }
    }
});
