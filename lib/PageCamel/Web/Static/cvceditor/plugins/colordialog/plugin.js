/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.

 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license

*/
CVCEDITOR.plugins.colordialog={requires:"dialog",lang:"en",init:function(b){var d=new CVCEDITOR.dialogCommand("colordialog");d.editorFocus=!1;b.addCommand("colordialog",d);CVCEDITOR.dialog.add("colordialog",this.path+"dialogs/colordialog.js");b.getColorFromDialog=function(d,g){var c,f,e;c=function(a){f(this);a="ok"==a.name?this.getValueOf("picker","selectedColor"):null;/^[0-9a-f]{3}([0-9a-f]{3})?$/i.test(a)&&(a="#"+a);d.call(g,a)};f=function(a){a.removeListener("ok",c);a.removeListener("cancel",c)};
e=function(a){a.on("ok",c);a.on("cancel",c)};b.execCommand("colordialog");if(b._.storedDialogs&&b._.storedDialogs.colordialog)e(b._.storedDialogs.colordialog);else CVCEDITOR.on("dialogDefinition",function(a){if("colordialog"==a.data.name){var b=a.data.definition;a.removeListener();b.onLoad=CVCEDITOR.tools.override(b.onLoad,function(a){return function(){e(this);b.onLoad=a;"function"==typeof a&&a.call(this)}})}})}}};CVCEDITOR.plugins.add("colordialog",CVCEDITOR.plugins.colordialog);