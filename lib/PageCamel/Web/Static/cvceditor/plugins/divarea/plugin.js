/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.
 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license
*/
CVCEDITOR.plugins.add("divarea",{afterInit:function(a){a.addMode("wysiwyg",function(c){var b=CVCEDITOR.dom.element.createFromHtml('\x3cdiv class\x3d"cke_wysiwyg_div cke_reset cke_enable_context_menu" hidefocus\x3d"true"\x3e\x3c/div\x3e');a.ui.space("contents").append(b);b=a.editable(b);b.detach=CVCEDITOR.tools.override(b.detach,function(a){return function(){a.apply(this,arguments);this.remove()}});a.setData(a.getData(1),c);a.fire("contentDom")})}});