package hide.tools;

class FileWatcher {

	var ide : hide.ui.Ide;
	var watches : Map<String,{ events : Array<{path:String,fun:Void->Void,checkDel:Bool}>, w : js.node.fs.FSWatcher, changed : Bool }> = new Map();

	public function new() {
		ide = hide.ui.Ide.inst;
	}

	public function register( path : String, updateFun, ?checkDelete : Bool ) {
		var w = getWatches(path);
		w.events.push({ path : path, fun : updateFun, checkDel : checkDelete });
	}

	public function unregister( path : String, updateFun ) {
		var w = getWatches(path);
		for( e in w.events )
			if( Reflect.compareMethods(e.fun, updateFun) ) {
				w.events.remove(e);
				break;
			}
		if( w.events.length == 0 ) {
			watches.remove(path);
			if( w.w != null ) w.w.close();
		}
	}

	function getWatches( path : String ) {
		var w = watches.get(path);
		if( w == null ) {
			w = {
				events : [],
				w : null,
				changed : false,
			};
			w.w = try js.node.Fs.watch(ide.getPath(path), function(k:String, file:String) {
				w.changed = true;
				haxe.Timer.delay(function() {
					if( !w.changed ) return;
					w.changed = false;
					for( e in w.events.copy() )
						if( k == "change" || e.checkDel )
							e.fun();
				}, 100);
			}) catch( e : Dynamic ) {
				// file does not exists, trigger a delayed event
				haxe.Timer.delay(function() {
					for( e in w.events )
						if( e.checkDel )
							e.fun();
				}, 0);
				return w;
			}
			watches.set(path, w);
		}
		return w;
	}


}