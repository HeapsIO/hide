package hide.comp;

class JsTools {
    public static function copyAttributes(to : Element, from : Element) {
        var old = from.get(0);
        var our = to.get(0);
        for (i in 0...old.attributes.length) {
            our.attributes.setNamedItem(cast old.attributes.item(i).cloneNode());
        }
    }
}