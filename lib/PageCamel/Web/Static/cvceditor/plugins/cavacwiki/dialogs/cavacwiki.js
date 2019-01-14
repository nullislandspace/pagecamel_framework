CVCEDITOR.dialog.add( 'cavacWikiDialog', function( editor ) {
    return {
        title: 'Cavac Wiki Articles',
        minWidth: 1200,
        minHeight: 200,

        contents: [
            {
                id: 'tab-basic',
                label: 'Settings',
                elements: [
                    {
                        type: 'text',
                        id: 'linktitle',
                        label: 'Link text',
                        validate: CVCEDITOR.dialog.validate.notEmpty( "Link text field cannot be empty." ),
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "linktitle" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "linktitle", this.getValue());
                        }
                    }
                ]
            },
            {
                id: 'tab-selector',
                label: 'Select Article',
                elements: [
                    {
                        type: 'html',
                        id: 'fileselect',
                        label: 'Select Article from library',
                        html: '<div id="fileselectelement">' +
                                '<table class="data" id="ArticleSelectTable">'+
                                '    <thead>'+
                                '        <tr class="tabheader">'+
                                '            <th>Link text</th>'+
                                '            <th>Display title</th>'+
                                '            <th>Teaser</th>'+
                                '        </tr>'+
                                '    </thead>   '+                        
                                '    <tbody>'+
                                '    </tbody>'+
                                '</table>'+
                                '</div>',
                        onLoad: function() {
                            //this.getElement().removeClass('cke_reset_all');
                        }
                    },
                    {
                        type: 'checkbox',
                        id: 'dummycheckbox',
                        label: 'Ignore this dummy checkbox'
                    }
                ]

            }
        ],
        onShow: function() {
            var selection = editor.getSelection();
            var element = selection.getStartElement();

            if ( element ) {
                element = element.getAscendant( 'a', true );
            }

            if ( !element || element.getName() != 'a' ) {
                element = editor.document.createElement( 'a' );
                element.setAttribute('class', 'cavacwiki');
                this.insertMode = true;
            } else {
                this.insertMode = false;
            }

            this.element = element;
            if ( !this.insertMode ) {
                this.setupContent( this.element );
            } else {
                var selectedText = selection.getSelectedText();
                this.setValueOf('tab-basic', 'linktitle', selectedText);
            }
            prepareArticleSelector();
        },
        onOk: function() {
            var dialog = this;
            
            var dialog = this;
            var a = this.element;
            this.commitContent( a );
            var linktitle = this.getValueOf('tab-basic', 'linktitle');
            a.setText(linktitle);

            if ( this.insertMode ) {
                editor.insertElement( a );
            }
        }
    };
});

function selectArticle(linktitle) {
    var mydialog = CVCEDITOR.dialog.getCurrent();
    mydialog.setValueOf('tab-basic', 'linktitle', linktitle);
    mydialog.selectPage('tab-basic');
    mydialog.getContentElement('tab-basic', 'linktitle').focus();
    return false;
}

var cvceditor_file_selector_prepared = 0;
function prepareArticleSelector() {
    if(cvceditor_file_selector_prepared == 1) {
        return;
    }
    $('#ArticleSelectTable').dataTable( {
                 serverSide: true,
                 ordering: true,
                 searching: true,
                 ajax: ttvars.wikiarticleselect,
                 serverMethod: "POST",
                 scrollY: 500,
                 scroller: {
                     loadingIndicator: true
                 },
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
                    "processing": '<img src="/static/loading_bar.gif' + ttvars.urlreloadpostfix + '">'
                 },
            });
    $('.cke_reset_all').removeClass('cke_reset_all');
    cvceditor_file_selector_prepared = 1;
}
