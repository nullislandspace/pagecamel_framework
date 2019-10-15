/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.
 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license
*/
(function(){CVCEDITOR.plugins.add("uploadfile",{requires:"uploadwidget,link",init:function(a){if(CVCEDITOR.plugins.clipboard.isFileApiSupported){var b=CVCEDITOR.fileTools;b.getUploadUrl(a.config)?b.addUploadWidget(a,"uploadfile",{uploadUrl:b.getUploadUrl(a.config),fileToElement:function(c){var a=new CVCEDITOR.dom.element("a");a.setText(c.name);a.setAttribute("href","#");return a},onUploaded:function(a){this.replaceWith('\x3ca href\x3d"'+a.url+'" target\x3d"_blank"\x3e'+a.fileName+"\x3c/a\x3e")}}):
CVCEDITOR.error("uploadfile-config")}}})})();
