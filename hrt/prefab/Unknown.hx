package hrt.prefab;

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
				Reflect.setField(data, f, copyValue(Reflect.getProperty(newData, f)));
			}
		}
	}

	override function save(to:Dynamic) {
		to.name = name;
		for (f in Reflect.fields(data)) {
			Reflect.setField(to, f, copyValue(Reflect.getProperty(data, f)));
		}
		return to;
	}

	static function copyValue(v:Dynamic) : Dynamic {
		switch (Type.typeof(v)) {
			case TClass(c):
				switch(c) {
					case cast Array:
						var v:Array<Dynamic> = v;
						return v.copy();
					case cast String:
						var v:String = v;
						return v;
					default:
						// TODO : oh no
						return haxe.Json.parse(haxe.Json.stringify(v));
				}
			default:
				return v;
		}
	}

#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "question-circle-o",
			name : "Unknown",
		};
	}

	override function edit( ctx : hide.prefab.EditContext ) {
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