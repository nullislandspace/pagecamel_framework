/*
 Copyright (c) 2003-2018, CKSource - Frederico Knabben. All rights reserved.
 For licensing, see LICENSE.md or https://cvceditor.com/legal/cvceditor-oss-license
*/
CVCEDITOR.plugins.add("menubutton",{requires:"button,menu",onLoad:function(){var d=function(c){var a=this._,b=a.menu;a.state!==CVCEDITOR.TRISTATE_DISABLED&&(a.on&&b?b.hide():(a.previousState=a.state,b||(b=a.menu=new CVCEDITOR.menu(c,{panel:{className:"cke_menu_panel",attributes:{"aria-label":c.lang.common.options}}}),b.onHide=CVCEDITOR.tools.bind(function(){var b=this.command?c.getCommand(this.command).modes:this.modes;this.setState(!b||b[c.mode]?a.previousState:CVCEDITOR.TRISTATE_DISABLED);a.on=
0},this),this.onMenu&&b.addListener(this.onMenu)),this.setState(CVCEDITOR.TRISTATE_ON),a.on=1,setTimeout(function(){b.show(CVCEDITOR.document.getById(a.id),4)},0)))};CVCEDITOR.ui.menuButton=CVCEDITOR.tools.createClass({base:CVCEDITOR.ui.button,$:function(c){delete c.panel;this.base(c);this.hasArrow=!0;this.click=d},statics:{handler:{create:function(c){return new CVCEDITOR.ui.menuButton(c)}}}})},beforeInit:function(d){d.ui.addHandler(CVCEDITOR.UI_MENUBUTTON,CVCEDITOR.ui.menuButton.handler)}});
CVCEDITOR.UI_MENUBUTTON="menubutton";
