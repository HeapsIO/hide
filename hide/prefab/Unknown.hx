package hide.prefab;

class Unknown extends Prefab {

	var data : Dynamic;

	override function load(v:Dynamic) {
		this.data = v;
	}

	override function save() {
		return data;
	}

	override function edit(ctx:EditContext) {
		#if editor
		ctx.properties.add(new hide.Element('<font color="red">Unknown prefab $type</font>'));
		#end
	}

	// do not register
}