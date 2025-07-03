package hide.tools;

typedef FileWatchEvent = {path:String,fun:Void->Void,checkDel:Bool,element:Element.HTMLElement,?ignoreCheck:String};

private typedef Watch = {
	path : String,
	events : Array<FileWatchEvent>,
	#if js
	w : js.node.fs.FSWatcher,
	lastStat : js.node.fs.Stats,
	#else
	w : hl.uv.Fs,
	#end
	wasChanged : Bool,
	changed : Bool,
	isDir : Bool,
	version : Int
};

class FileWatcher {

	var ide : hide.Ide;
	var watches : Map<String, Watch> = new Map();
	var timer : haxe.Timer;

	public function new() {
		ide = hide.Ide.inst;
	}

	public function pause() {
		for( w in watches )
			if( w.w != null ) {
				var sign = getSignature(w.path);
				if( sign != null ) {
					for( f in w.events )
						f.ignoreCheck = sign;
				}
				w.w.close();
				w.w = null;
			}
	}

	public function resume() {
		for( w in watches )
			if( w.w == null && w.events.length > 0 ) {
				try initWatch(w) catch( e : Dynamic ) {
					// file does not exists, trigger a delayed event
					haxe.Timer.delay(function() {
						for( e in w.events.copy() )
							if( isLive(w.events,e) && e.checkDel )
								e.fun();
					}, 0);
					return;
				}

				var sign = getSignature(w.path);
				for( f in w.events )
					if( f.ignoreCheck != sign || w.isDir ) {
						w.changed = true;
						w.version++;
						w.wasChanged = sign != null;
						break;
					}
				if( w.changed )
					haxe.Timer.delay(onEventChanged.bind(w),0);
			}
	}

	public function ignorePrevChange( f : FileWatchEvent ) {
		f.ignoreCheck = getSignature(f.path);
	}

	function getSignature( path : String ) : String {
		#if js
		var sign = js.node.Crypto.createHash(js.node.Crypto.CryptoAlgorithm.MD5);
		try {
			sign.update(js.node.Fs.readFileSync(ide.getPath(path)));
			return sign.digest("base64");
		} catch( e : Dynamic ) {
			return null;
		}
		#else
		return "";
		#end
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

	public function register( path : String, updateFun, ?checkDelete : Bool, ?element : Element ) : FileWatchEvent {
		path = ide.getPath(path);
		var w = getWatches(path);
		var f : FileWatchEvent = { path : path, fun : updateFun, checkDel : checkDelete, element : element == null ? null : element.get(0) };
		w.events.push(f);
		if( element != null && timer == null ) {
			timer = new haxe.Timer(1000);
			timer.run = cleanEvents;
		}
		return f;
	}

	public function registerRaw( path : String, updateFun, ?checkDelete : Bool, ?element : Element.HTMLElement) : FileWatchEvent {
		path = ide.getPath(path);
		var w = getWatches(path);
		var f : FileWatchEvent = { path : path, fun : updateFun, checkDel : checkDelete, element: element};
		w.events.push(f);
		if( element != null && timer == null ) {
			timer = new haxe.Timer(1000);
			timer.run = cleanEvents;
		}
		return f;
	}

	public function unregister( path : String, updateFun : Void -> Void ) {
		path = ide.getPath(path);
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
				if( e.element == element.get(0) )
					w.events.remove(e);
			if( w.events.length == 0 ) {
				watches.remove(path);
				if( w.w != null ) w.w.close();
			}
		}
	}

	public function getVersion( path : String ) : Int {
		var w = watches.get(ide.getPath(path));
		if( w == null )
			return 0;
		return w.version;
	}

	public function isChangePending( f : FileWatchEvent ) : Bool {
		var w = watches.get(f.path);
		if( w != null && w.changed ) {
			if( f.ignoreCheck != null ) {
				var sign = getSignature(w.path);
				if( sign == f.ignoreCheck )
					return false;
			}
			return true;
		}
		return false;
	}

	function cleanEvents() {
		for( w in watches )
			for( e in w.events.copy() )
				isLive(w.events, e);
	}

	function isLive( events : Array<FileWatchEvent>, e : FileWatchEvent ) {
		if( e.element == null ) return true;
		#if js
		var elt = e.element;
		while( elt != null ) {
			if( elt.nodeName == "BODY" ) return true;
			elt = elt.parentElement;
		}
		#else
		var elt = e.element;
		if( elt != null && @:privateAccess elt.element.getScene() != null ) return true;
		#end
		events.remove(e);
		return false;
	}

	function onEventChanged( w : Watch ) {
		if( !w.changed ) return;
		w.changed = false;
		var sign = null;
		for( e in w.events.copy() )
			if( isLive(w.events,e) && (w.wasChanged || e.checkDel) ) {
				if( e.ignoreCheck != null ) {
					if( sign == null ) sign = getSignature(w.path);
					if( sign == e.ignoreCheck ) continue;
					e.ignoreCheck = null;
				}
				e.fun();
			}
		w.wasChanged = false;
	}

	function initWatch( w : Watch ) {
		#if js
		w.lastStat = js.node.Fs.statSync(w.path);
		w.w = js.node.Fs.watch(w.path, {persistent: true}, function(k:String, file:String) {
			if( w.isDir && k == "change" ) return;
			if( k == "change" ) {
				// for an unknown reason (maybe SVN ?), sometimes changes are triggered without the file being actually changed.
				// we check that here
				var oldStat = w.lastStat;
				w.lastStat = js.node.Fs.statSync(w.path);
				if (w.lastStat.mtime.getTime() <= oldStat.mtime.getTime() &&
					w.lastStat.ctime.getTime() <= oldStat.ctime.getTime()) {
					return;
				}
				w.wasChanged = true;
			}
			if( w.changed ) return;
			w.changed = true;
			w.version++;
			haxe.Timer.delay(onEventChanged.bind(w),100);
		});
		#else
		w.w = new hl.uv.Fs(w.path, function(ev) {
			if( w.isDir && ev == Change ) return;
			if( ev == Change ) w.wasChanged = true;
			if( w.changed ) return;
			w.changed = true;
			w.version++;
			haxe.Timer.delay(onEventChanged.bind(w),100);
		});
		#end
	}

	function getWatches( path : String ) {
		var w = watches.get(path);
		if( w == null ) {
			var fullPath = ide.getPath(path);
			w = {
				path : fullPath,
				events : [],
				w : null,
				changed : false,
				isDir : try sys.FileSystem.isDirectory(fullPath) catch( e : Dynamic ) false,
				wasChanged : false,
				version : 0,
				#if js
				lastStat: null,
				#end
			};
			try initWatch(w) catch( e : Dynamic ) {
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