package hide.prefab;

class Resource extends hxd.res.Resource {

	var lib : Library;

	public function load() : Library {
		if( lib != null )
			return lib;
		var data = haxe.Json.parse(entry.getText());
		if(data.type == "level3d")
			lib = new hide.prefab.l3d.Level3D();
		else
			lib = new Library();
		lib.load(data);
		watch(function() lib.reload(haxe.Json.parse(entry.getText())));
		return lib;
	}

}