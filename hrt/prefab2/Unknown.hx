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
        return to;
    }

#if editor
    override function getHideProps() : hide.prefab2.HideProps {
        return {
            icon : "question-circle-o",
            name : "Unknown",
        };
    }

	override function edit( ctx : hide.prefab2.EditContext ) {
		var props = new hide.Element('
            <p>Unknown prefab type : <code>${data.type}</code></p>
            <p>This prefab might has been saved in a more recent version of hide (in that case try to update), or this type no longer exists. </p>
            <p>No data will be lost if this prefab is saved, but rendering glitches or strange offsets can occur.</p>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}
#end
}