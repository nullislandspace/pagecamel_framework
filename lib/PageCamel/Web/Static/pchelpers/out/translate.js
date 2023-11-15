export function translateString(translate) {
    var translations = window.maskconfig.translations;
    for (var i = 0; i < translations.length; i++) {
        if (translations[i].key == translate) {
            return translations[i].value;
        }
    }
    return translate;
}
//# sourceMappingURL=translate.js.map