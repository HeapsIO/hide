package hrt.prefab;

class Unknown extends Prefab {

	@:c var data : Dynamic;

	public function getPrefabType() {
		return data.type;
	}

	override function load(v:Dynamic) {
		this.data = Reflect.copy(v);
		Reflect.deleteField(this.data, "children");
	}

	override function save() {
		return Reflect.copy(data);
	}

	override function getDefaultName():String {
		return "unknown";
	}

	#if editor
	override function edit(ctx:hide.prefab.EditContext) {
		ctx.properties.add(new hide.Element('<font color="red">Unknown prefab $type</font>'));
	}
	#end


}