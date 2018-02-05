package hide.prefab;

class Resource extends hxd.res.Resource {

	var lib : Library;

	public function load() : Library {
		if( lib != null )
			return lib;
		lib = new Library();
		lib.load(haxe.Json.parse(entry.getText()));
		watch(function() lib.reload(haxe.Json.parse(entry.getText())));
		return lib;
	}

}