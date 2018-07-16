package hide.prefab;

class Resource extends hxd.res.Resource {

	var lib : hxd.prefab.Library;

	public function load() : hxd.prefab.Library {
		if( lib != null )
			return lib;
		var data = haxe.Json.parse(entry.getText());
		var lib : hxd.prefab.Library = switch(data.type) {
			case "level3d": new hide.prefab.l3d.Level3D();
			case "fx": new hide.prefab.fx.FX();
			default: new hxd.prefab.Library();
		}
		lib.load(data);
		watch(function() lib.reload(haxe.Json.parse(entry.getText())));
		return lib;
	}

}