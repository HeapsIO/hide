package hrt.prefab2;

// Unknown prefab storage
class Unknown extends Prefab {
    public var data : Dynamic = null;

    override function load(newData: Dynamic) : Void {
        data = {};

        for (f in Reflect.fields(newData)) {
            if (f == "name") {
                name = newData.name;
            }
            else if (f != "children") {
                Reflect.setField(data, f, Prefab.copyValue(Reflect.getProperty(newData, f)));
            }
        }
    }

    override function save(to:Dynamic) {
        to.name = name;
        for (f in Reflect.fields(data)) {
            Reflect.setField(to, f, Prefab.copyValue(Reflect.getProperty(data, f)));
        }
    }

#if editor
    override function getHideProps() : hide.prefab2.HideProps {
        return {
            icon : "question-circle-o",
            name : "unknown",
        };
    }
#end
}