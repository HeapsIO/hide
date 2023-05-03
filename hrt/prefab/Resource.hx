package hrt.prefab;

class Resource extends hxd.res.Resource {

	var lib : Prefab;
	var cacheVersion : Int;
	var isWatched : Bool;

	override function watch( onChanged: Null<Void -> Void> ) {
		if( entry == null )
			return;
		if( onChanged == null ) {
			super.watch(null);
			isWatched = false;
			return;
		}
		isWatched = true;
		super.watch(function() {
			if( lib != null ) {
				var data = try loadData() catch( e : Dynamic ) return; // parsing error (conflict ?)
				lib.reload(data);
				onPrefabLoaded(lib);
			}
			onChanged();
		});
	}

	function loadData() {
		var isBSON = entry.fetchBytes(0,1).get(0) == 'H'.code;
		return isBSON ? new hxd.fmt.hbson.Reader(entry.getBytes(),false).read() : haxe.Json.parse(entry.getText());
	}

	public function load() : Prefab {
		if( lib != null && cacheVersion == CACHE_VERSION )
			return lib;
		var data = loadData();
		lib = Library.create(entry.extension);
		lib.loadData(data);
		cacheVersion = CACHE_VERSION;
		onPrefabLoaded(lib);
		if( !isWatched )
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