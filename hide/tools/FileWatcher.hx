package hide.tools;

private typedef FileEvent = {path:String,fun:Void->Void,checkDel:Bool,element:js.html.Element};

class FileWatcher {

	var ide : hide.Ide;
	var watches : Map<String,{ events : Array<FileEvent>, w : js.node.fs.FSWatcher, ignoreNext : Int, wasChanged : Bool, changed : Bool, isDir : Bool }> = new Map();
	var timer : haxe.Timer;

	public function new() {
		ide = hide.Ide.inst;
	}

	public function ignoreNextChange( path : String ) {
		var w = getWatches(path);
		w.ignoreNext++;
	}

	public function dispose() {
		if( timer != null ) {
			timer.stop();
			timer = null;
		}
		for( w in watches )
			if( w.w != null )
				w.w.close();
		watches = new Map();
	}

	public function register( path : String, updateFun, ?checkDelete : Bool, ?element : Element ) {
		var w = getWatches(path);
		w.events.push({ path : path, fun : updateFun, checkDel : checkDelete, element : element == null ? null : element[0] });
		if( element != null && timer == null ) {
			timer = new haxe.Timer(1000);
			timer.run = cleanEvents;
		}
	}

	public function unregister( path : String, updateFun : Void -> Void ) {
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

	public function unregisterElement( element : Element ) {
		for( path => w in watches ) {
			for( e in w.events.copy() )
				if( e.element == element[0] )
					w.events.remove(e);
			if( w.events.length == 0 ) {
				watches.remove(path);
				if( w.w != null ) w.w.close();
			}
		}
	}

	function cleanEvents() {
		for( w in watches )
			for( e in w.events.copy() )
				isLive(w.events, e);
	}

	function isLive( events : Array<FileEvent>, e : FileEvent ) {
		if( e.element == null ) return true;
		var elt = e.element;
		while( elt != null ) {
			if( elt.nodeName == "BODY" ) return true;
			elt = elt.parentElement;
		}
		events.remove(e);
		return false;
	}

	function getWatches( path : String ) {
		var w = watches.get(path);
		if( w == null ) {
			var fullPath = ide.getPath(path);
			w = {
				events : [],
				w : null,
				changed : false,
				isDir : try sys.FileSystem.isDirectory(fullPath) catch( e : Dynamic ) false,
				ignoreNext : 0,
				wasChanged : false,
			};
			w.w = try js.node.Fs.watch(fullPath, function(k:String, file:String) {
				if( w.isDir && k == "change" ) return;
				if( k == "change" ) w.wasChanged = true;
				if( w.changed ) return;
				w.changed = true;
				haxe.Timer.delay(function() {
					if( !w.changed ) return;
					w.changed = false;
					if( w.ignoreNext > 0 ) {
						w.ignoreNext--;
						return;
					}
					for( e in w.events.copy() )
						if( isLive(w.events,e) && (w.wasChanged || e.checkDel) )
							e.fun();
					w.wasChanged = false;
				}, 100);
			}) catch( e : Dynamic ) {
				// file does not exists, trigger a delayed event
				haxe.Timer.delay(function() {
					for( e in w.events.copy() )
						if( isLive(w.events,e) && e.checkDel )
							e.fun();
				}, 0);
				return w;
			}
			watches.set(path, w);
		}
		return w;
	}


}