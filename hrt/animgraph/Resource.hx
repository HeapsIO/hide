package hrt.animgraph;

@:access(hrt.prefab.AnimGraph)
class Resource extends hxd.res.Resource {

	var animGraph : AnimGraph;
	var cacheVersion : Int;
	var isWatched : Bool;

	function loadData() {
		var isBSON = entry.fetchBytes(0,1).get(0) == 'H'.code;
		return isBSON ? new hxd.fmt.hbson.Reader(entry.getBytes(),false).read() : haxe.Json.parse(entry.getText());
	}

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
			if( animGraph != null ) {
				var data = try loadData() catch( e : Dynamic ) return; // parsing error (conflict ?)
				animGraph.reload(data);
			}
			onChanged();
		});
	}

	public function load() : hrt.animgraph.AnimGraph {
		if( animGraph != null && cacheVersion == CACHE_VERSION )
			return animGraph;
		var data = loadData();
		animGraph = Std.downcast(@:privateAccess hrt.prefab.Prefab.createFromDynamic(data, new hrt.prefab.ContextShared(entry.path, false)), hrt.animgraph.AnimGraph);
		cacheVersion = CACHE_VERSION;
		watch(function() {}); // auto lib reload
		return animGraph;
	}

	public function loadAnim() : AnimGraphInstance {
		return load().getAnimation();
	}

	public static var CACHE_VERSION = 0;
}