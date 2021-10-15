package hrt.prefab;

class Unknown extends Prefab {

	@:c var data : Dynamic;

	public function getPrefabType() {
		return data.type;
	}

	override function load(v:Dynamic) {
		this.data = Reflect.copy(v);
		this.props = v.props;
		Reflect.deleteField(this.data, "children");
		Reflect.deleteField(this.data, "props");
	}

	override function save() {
		var data : Dynamic = Reflect.copy(data);
		if( this.props != null ) data.props = props;
		return data;
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