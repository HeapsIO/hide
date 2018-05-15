package hide.prefab;

class Resource extends hxd.res.Resource {

	var lib : Library;

	public function load() : Library {
		if( lib != null )
			return lib;
		var data = haxe.Json.parse(entry.getText());
		var lib : Library = switch(data.type) {
			case "level3d": new hide.prefab.l3d.Level3D();
			case "fx": new hide.prefab.fx.FXScene();
			default: new Library();
		}
		lib.load(data);
		watch(function() lib.reload(haxe.Json.parse(entry.getText())));
		return lib;
	}

}