/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.

 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license

*/
CVCEDITOR.plugins.add("uicolor",{requires:"dialog",lang:"en",icons:"uicolor",hidpi:!0,init:function(a){var b=new CVCEDITOR.dialogCommand("uicolor");b.editorFocus=!1;CVCEDITOR.dialog.add("uicolor",this.path+"dialogs/uicolor.js");a.addCommand("uicolor",b);a.ui.addButton&&a.ui.addButton("UIColor",{label:a.lang.uicolor.title,command:"uicolor",toolbar:"tools,1"})}});