/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.

 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license

*/
CVCEDITOR.plugins.add("docprops",{requires:"wysiwygarea,dialog,colordialog",lang:"en",icons:"docprops,docprops-rtl",hidpi:!0,init:function(a){var b=new CVCEDITOR.dialogCommand("docProps");b.modes={wysiwyg:a.config.fullPage};b.allowedContent={body:{styles:"*",attributes:"dir"},html:{attributes:"lang,xml:lang"}};b.requiredContent="body";a.addCommand("docProps",b);CVCEDITOR.dialog.add("docProps",this.path+"dialogs/docprops.js");a.ui.addButton&&a.ui.addButton("DocProps",{label:a.lang.docprops.label,command:"docProps",
toolbar:"document,30"})}});