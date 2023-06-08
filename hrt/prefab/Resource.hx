package hrt.prefab;

class Resource extends hxd.res.Resource {

	var prefab : Prefab;
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
			if( prefab != null ) {
				var data = try loadData() catch( e : Dynamic ) return; // parsing error (conflict ?)
				prefab.reload(data);
				onPrefabLoaded(prefab);
			}
			onChanged();
		});
	}

	function loadData() {
		var isBSON = entry.fetchBytes(0,1).get(0) == 'H'.code;
		return isBSON ? new hxd.fmt.hbson.Reader(entry.getBytes(),false).read() : haxe.Json.parse(entry.getText());
	}

	public function load(?shared: ContextShared) : Prefab {
		if( prefab != null && cacheVersion == CACHE_VERSION )
			return prefab;
		var data = loadData();
		prefab = Prefab.createFromDynamic(data);
		prefab.shared.prefabSource = entry.path;
		prefab.shared.currentPath = entry.path;
		cacheVersion = CACHE_VERSION;
		onPrefabLoaded(prefab);
		watch(function() {}); // auto lib reload
		return cast prefab;
	}

	public function load2d(?shared: ContextShared) : Object2D {
		if( Std.downcast(prefab, Object2D) != null && cacheVersion == CACHE_VERSION )
			return cast prefab;
		var data = loadData();
		prefab = Std.downcast(Prefab.createFromDynamic(data), Object2D);
		prefab.shared.prefabSource = entry.path;
		prefab.shared.currentPath = entry.path;
		cacheVersion = CACHE_VERSION;
		onPrefabLoaded(prefab);
		watch(function() {}); // auto lib reload
		return cast prefab;
	}

	public static function make( p : Object3D ) {
		if( p == null ) throw "assert";
		var r = new Resource(null);
		r.prefab = p;
		return r;
	}

	public static var CACHE_VERSION = 0;
	public static dynamic function onPrefabLoaded(p:Prefab) {
	}

}