CKEDITOR.dialog.add( 'cavacFilesDialog', function( editor ) {
    return {
        title: 'Cavac Files',
        minWidth: 1200,
        minHeight: 200,

        contents: [
            {
                id: 'tab-basic',
                label: 'Settings',
                elements: [
                    {
                        type: 'text',
                        id: 'href',
                        label: 'Relative Path',
                        validate: CKEDITOR.dialog.validate.notEmpty( "Path can not be empty" ),
                        //validate: CKEDITOR.dialog.validate.notEmpty( "Popup title field cannot be empty." ),
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "href" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "href", this.getValue() );
                        }
                    },
                    {
                        type: 'text',
                        id: 'linktext',
                        label: 'Link text',
                        validate: CKEDITOR.dialog.validate.notEmpty( "Link text field cannot be empty." ),
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "linktext" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "linktext", this.getValue());
                            //element.setText(this.getValue());
                        }
                    },
                    {
                        type: 'text',
                        id: 'title',
                        label: 'Description',
                        //validate: CKEDITOR.dialog.validate.notEmpty( "Popup title field cannot be empty." ),
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "title" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "title", this.getValue() );
                        }
                    },
                    {
                        type: 'text',
                        id: 'bytesize',
                        label: 'size in bytes',
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "size" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "size", this.getValue() );
                        }
                    },
                    {
                        type: 'text',
                        id: 'humansize',
                        label: 'Human readable size',
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "size" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "size", this.getValue() );
                        }
                    }
                ]
            },
            {
                id: 'tab-selector',
                label: 'Select File',
                elements: [
                    {
                        type: 'html',
                        id: 'fileselect',
                        label: 'Select File from library',
                        html: '<div id="fileselectelement">' +
                                '<table class="data" id="FileSelectTable">'+
                                '    <thead>'+
                                '        <tr class="tabheader">'+
                                '            <th>Filename</th>'+
                                '            <th>Description</th>'+
                                '            <th>Filesize</th>'+
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
                element.setAttribute('class', 'cavacfiles');
                this.insertMode = true;
            } else {
                this.insertMode = false;
            }

            this.element = element;
            if ( !this.insertMode ) {
                this.setupContent( this.element );
            } else {
                var selectedText = selection.getSelectedText();
                this.setValueOf('tab-basic', 'linktext', selectedText);
            }
            prepareFileSelector();
        },
        onOk: function() {
            var dialog = this;
            
            var dialog = this;
            var a = this.element;
            this.commitContent( a );
            var inputlinktext = this.getValueOf('tab-basic', 'linktext');
            var inputhumansize = this.getValueOf('tab-basic', 'humansize');
            var displaylinktext = inputlinktext + ' (' + inputhumansize + ')';
            a.setText(displaylinktext);

            if ( this.insertMode ) {
                editor.insertElement( a );
            }
        }
    };
});

function selectFile(filename, description, filesize_bytes, filesize_human) {
    var mydialog = CKEDITOR.dialog.getCurrent();
    mydialog.setValueOf('tab-basic', 'href', filename);
    mydialog.setValueOf('tab-basic', 'title', description + ' (' + filesize_bytes + ' bytes)');
    mydialog.setValueOf('tab-basic', 'bytesize', filesize_bytes);
    mydialog.setValueOf('tab-basic', 'humansize', filesize_human);
    mydialog.selectPage('tab-basic');
    mydialog.getContentElement('tab-basic', 'linktext').focus();
    return false;
}

var ckeditor_file_selector_prepared = 0;
function prepareFileSelector() {
    if(ckeditor_file_selector_prepared == 1) {
        return;
    }
    $('#FileSelectTable').dataTable( {
                 serverSide: true,
                 ordering: true,
                 searching: true,
                 ajax: "/blog/files/select",
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
    ckeditor_file_selector_prepared = 1;
}
