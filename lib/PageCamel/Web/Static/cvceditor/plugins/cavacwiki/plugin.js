CVCEDITOR.plugins.add('cavacwiki', {
    icons: 'cavacwiki',
    init: function(editor) {
        editor.addCommand('cavacwiki', new CVCEDITOR.dialogCommand('cavacWikiDialog'), {
            allowedContent: 'a[class,linktitle]'
        });
        editor.ui.addButton('cavacwiki', {
            label: 'Wiki Link',
            command: 'cavacwiki',
            toolbar: 'insert'
        });
        CVCEDITOR.dialog.add( 'cavacWikiDialog', this.path + 'dialogs/cavacwiki.js' );
        
        // Context menu for editing existing notes
        if(editor.contextMenu) {
            editor.addMenuGroup('cavacGroup');
            editor.addMenuItem('cavacwikiItem', {
                label: "Edit Wiki link",
                icon: this.path + 'icons/cavacwiki.png',
                command: 'cavacwiki',
                group: 'cavacGroup'
            });
            
            editor.contextMenu.addListener( function(element) {
                var isCavacFiles = (element.is( 'a' ) && (element.hasClass('cavacwiki')))
                    || (element.hasAscendant( 'a' ) && element.getAscendant('a').hasClass('cavacwiki'));
                if(isCavacFiles) {
                    return { cavacwikiItem: CVCEDITOR.TRISTATE_OFF};
                }
                
            });
        }
    }
});
