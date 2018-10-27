/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.

 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license

*/
CVCEDITOR.plugins.add("print",{lang:"en",icons:"print,",hidpi:!0,init:function(a){a.elementMode!=CVCEDITOR.ELEMENT_MODE_INLINE&&(a.addCommand("print",CVCEDITOR.plugins.print),a.ui.addButton&&a.ui.addButton("Print",{label:a.lang.print.toolbar,command:"print",toolbar:"document,50"}))}});CVCEDITOR.plugins.print={exec:function(a){CVCEDITOR.env.gecko?a.window.$.print():a.document.$.execCommand("Print")},canUndo:!1,readOnly:1,modes:{wysiwyg:1}};