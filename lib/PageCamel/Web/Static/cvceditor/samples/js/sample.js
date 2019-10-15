/**
 * Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.
 * For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license
 */

/* exported initSample */

if ( CVCEDITOR.env.ie && CVCEDITOR.env.version < 9 )
    CVCEDITOR.tools.enableHtml5Elements( document );

// The trick to keep the editor in the sample quite small
// unless user specified own height.
CVCEDITOR.config.height = 150;
CVCEDITOR.config.width = 'auto';

var initSample = ( function() {
    var wysiwygareaAvailable = isWysiwygareaAvailable(),
        isBBCodeBuiltIn = !!CVCEDITOR.plugins.get( 'bbcode' );

    return function() {
        var editorElement = CVCEDITOR.document.getById( 'editor' );

        // :(((
        if ( isBBCodeBuiltIn ) {
            editorElement.setHtml(
                'Hello world!\n\n' +
                'I\'m an instance of [url=https://cvceditor.com]CVCEditor[/url].'
            );
        }

        // Depending on the wysiwygare plugin availability initialize classic or inline editor.
        if ( wysiwygareaAvailable ) {
            CVCEDITOR.replace( 'editor' );
        } else {
            editorElement.setAttribute( 'contenteditable', 'true' );
            CVCEDITOR.inline( 'editor' );

            // TODO we can consider displaying some info box that
            // without wysiwygarea the classic editor may not work.
        }
    };

    function isWysiwygareaAvailable() {
        // If in development mode, then the wysiwygarea must be available.
        // Split REV into two strings so builder does not replace it :D.
        if ( CVCEDITOR.revision == ( '%RE' + 'V%' ) ) {
            return true;
        }

        return !!CVCEDITOR.plugins.get( 'wysiwygarea' );
    }
} )();

