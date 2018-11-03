CKEDITOR.dialog.add( 'cavacImageDialog', function( editor ) {
    return {
        title: 'Cavac Image',
        minWidth: 1200,
        minHeight: 600,

        contents: [
            {
                id: 'tab-basic',
                label: 'Settings',
                elements: [
                    {
                        type: 'text',
                        id: 'src',
                        label: 'Relative Path',
                        validate: CKEDITOR.dialog.validate.notEmpty( "Path can not be empty" ),
                        //validate: CKEDITOR.dialog.validate.notEmpty( "Popup title field cannot be empty." ),
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "src" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "src", this.getValue() );
                        }
                    },
                    {
                        type: 'text',
                        id: 'title',
                        label: 'Title/Hover text',
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
                        id: 'alt',
                        label: 'Alt text',
                        setup: function( element ) {
                            this.setValue( element.getAttribute( "alt" ) );
                        },

                        commit: function( element ) {
                            element.setAttribute( "alt", this.getValue() );
                        }
                    },
                    {
                        type: 'checkbox',
                        id: 'border',
                        label: 'Border',
                        setup: function( element ) {
                            var border = element.getAttribute( "border" );
                            if(border == '1') {
                                this.setValue( true );
                            } else {
                                this.setValue( false );
                            }
                        },

                        commit: function( element ) {
                            var border = this.getValue();
                            if(border == true) {
                                border = '1';
                            } else {
                                border = '0';
                            }
                            element.setAttribute( "border",  border);
                        }
                    }
                ]
            },
            {
                id: 'tab-selector',
                label: 'Select Image',
                elements: [
                    {
                        type: 'html',
                        id: 'imageselect',
                        label: 'Select Image from library',
                        html: '<div id="imageselectelement">' +
                                '<table class="data" id="ImageSelectTable">'+
                                '    <thead>'+
                                '        <tr class="tabheader">'+
                                '            <th>Preview</th>'+
                                '            <th>Filename</th>'+
                                '            <th>Description</th>'+
                                '            <th>Width</th>'+
                                '            <th>Height</th>'+
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
                    }/*,
                    {
                        type: 'button',
                        id: 'resetbutton',
                        label: 'Class reset button',
                        onClick: function() {
                            $('#imageselectelement > .cke_reset_all').each(function() {
                                console.log($(this));
                                $(this).removeClass('cke_reset_all');
                            });
                        }
                        
                    },
                    {
                        type: 'button',
                        id: 'initbutton',
                        label: 'Load Table',
                        onClick: function() {
                            prepareImageSelector();
                        }
                        
                    }*/
                ]
            }
        ],
        onShow: function() {
            var selection = editor.getSelection();
            var element = selection.getStartElement();

            if ( element ) {
                element = element.getAscendant( 'img', true );
            }

            if ( !element || element.getName() != 'img' ) {
                element = editor.document.createElement( 'img' );
                element.setAttribute('class', 'cavacimage');
                this.insertMode = true;
            } else {
                this.insertMode = false;
            }

            this.element = element;
            if ( !this.insertMode ) {
                this.setupContent( this.element );
            } else {
                var selectedText = selection.getSelectedText();
                this.setValueOf('tab-basic', 'title', selectedText);
                this.setValueOf('tab-basic', 'border', '1');
            }
            prepareImageSelector();
        },
        onOk: function() {
            var dialog = this;
            
            var dialog = this;
            var img = this.element;
            this.commitContent( img );

            if ( this.insertMode ) {
                editor.insertElement( img );
            }
        }
    };
});

function selectImage(filename, description) {
    var mydialog = CKEDITOR.dialog.getCurrent();
    mydialog.setValueOf('tab-basic', 'src', filename);
    mydialog.setValueOf('tab-basic', 'alt', description);
    mydialog.selectPage('tab-basic');
    mydialog.getContentElement('tab-basic', 'title').focus();
    return false;
}

var ckeditor_image_selector_prepared = 0;
function prepareImageSelector() {
    if(ckeditor_image_selector_prepared == 1) {
        return;
    }
    $('#ImageSelectTable').dataTable( {
                 serverSide: true,
                 ordering: true,
                 searching: true,
                 ajax: "/blog/images/select",
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
    ckeditor_image_selector_prepared = 1;
}
