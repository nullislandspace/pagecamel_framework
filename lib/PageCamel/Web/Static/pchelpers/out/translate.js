"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.translateString = void 0;
function translateString(translate) {
    var translations = window.maskconfig.translations;
    for (var i = 0; i < translations.length; i++) {
        if (translations[i].key == translate) {
            return translations[i].value;
        }
    }
    return translate;
}
exports.translateString = translateString;
//# sourceMappingURL=translate.js.map