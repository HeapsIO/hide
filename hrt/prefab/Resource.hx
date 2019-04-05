package hrt.prefab;

class Resource extends hxd.res.Resource {

	var lib : Prefab;

	public function load() : Prefab {
		if( lib != null )
			return lib;
		var data = haxe.Json.parse(entry.getText());
		lib = Library.create(entry.extension);
		lib.loadData(data);
		watch(function() lib.reload(haxe.Json.parse(entry.getText())));
		return lib;
	}

}