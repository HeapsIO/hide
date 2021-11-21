package hrt.prefab;

class Resource extends hxd.res.Resource {

	var lib : Prefab;
	var cacheVersion : Int;

	override function watch( onChanged: Null<Void -> Void> ) {
		if( entry == null )
			return;
		if( onChanged == null ) {
			super.watch(null);
			return;
		}
		super.watch(function() {
			if( lib != null ) {
				var data = try haxe.Json.parse(entry.getText()) catch( e : Dynamic ) return; // parsing error (conflict ?)
				lib.reload(data);
				onPrefabLoaded(lib);
			}
			onChanged();
		});
	}

	public function load() : Prefab {
		if( lib != null && cacheVersion == CACHE_VERSION )
			return lib;
		var isBSON = entry.fetchBytes(0,1).get(0) == 'H'.code;
		var data = isBSON ? new hxd.fmt.hbson.Reader(entry.getBytes(),false).read() : haxe.Json.parse(entry.getText());
		lib = Library.create(entry.extension);
		lib.loadData(data);
		cacheVersion = CACHE_VERSION;
		onPrefabLoaded(lib);
		watch(function() {}); // auto lib reload
		return lib;
	}

	public static function make( p : Prefab ) {
		if( p == null ) throw "assert";
		var r = new Resource(null);
		r.lib = p;
		return r;
	}

	public static var CACHE_VERSION = 0;
	public static dynamic function onPrefabLoaded(p:Prefab) {
	}

}