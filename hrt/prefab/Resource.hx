package hrt.prefab;

@:access(hrt.prefab.Prefab)
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
		#if editor
		// Force loading the original prefab data from disc to avoid sync errors between
		// original data and bson
		var localEntry = Std.downcast(entry, hxd.fs.LocalFileSystem.LocalEntry);
		@:privateAccess var path = localEntry.originalFile ?? localEntry.file;
		return  haxe.Json.parse(sys.io.File.getContent(path));
		#else
		var isBSON = entry.fetchBytes(0,1).get(0) == 'H'.code;
		return isBSON ? new hxd.fmt.hbson.Reader(entry.getBytes(),false).read() : haxe.Json.parse(entry.getText());
		#end
	}

	public function loadBypassCache() : Prefab {
		var data = loadData();
		var prefab = Prefab.createFromDynamic(data, new ContextShared(entry.path, false));
		return cast prefab;
	}

	public function load() : Prefab {
		if(prefab != null && cacheVersion == CACHE_VERSION )
			return prefab;
		prefab = loadBypassCache();
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