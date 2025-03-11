package hrt.impl;

class BuildTools {

	static function log( str : String ) {
		#if hl
		Sys.println(str);
		#else
		trace(str);
		#end
		hxd.System.timeoutTick();
	}

	/**
		Build all files in `baseDir` directory (default: `res/`).
	 */
	public static function buildAllFiles( ?baseDir : String, ?onProgress : (percent:Float, currentFile:String) -> Void, ?onError : String -> Void, ?onDone : (count:Int) -> Void ) {
		log("[INFO] Start building all files " + Date.now());
		var baseDir = baseDir ?? "res/";
		function getPath(path : String) {
			return baseDir + path;
		}
		var onProgress = onProgress ?? function(percent, currentFile) {
			log('[PROGRESS] ($percent%) $currentFile');
		};
		var onError = onError ?? function(msg) {
			log('[INFO] $msg');
		};
		var onDone = onDone ?? function(count) {
		};
		var startTime = haxe.Timer.stamp();
		var lastTime = startTime;
		var all = [""];
		var errors = [];
		var done = 0;
		function loop() {
			while( true ) {
				if( all.length == 0 ) {
					onProgress(100, "");
					log("[INFO] Finished building " + done + " directory/files " + Date.now());
					if( errors.length > 0 ) {
						onError("Errors during Build Files:\n" + errors.join("\n"));
					}
					onDone(done);
					return;
				}
				if( haxe.Timer.stamp() - lastTime > 0.1 ) {
					lastTime = haxe.Timer.stamp();
					onProgress(Std.int(done*1000/(done+all.length))/10, all[0]);
					haxe.Timer.delay(loop, 0);
					return;
				}
				var path = all.shift();
				var e = try hxd.res.Loader.currentInstance.load(path).entry catch( e ) {
					if( path != "" ) { // skip root error
						errors.push(e.message);
					}
					null;
				}
				if( e == null && path == "" ) e = hxd.res.Loader.currentInstance.fs.getRoot();
				if( e != null ) done++;
				if( e != null && e.isDirectory ) {
					var base = path;
					if( base != "" ) base += "/";
					for( f in sys.FileSystem.readDirectory(getPath(path)) ) {
						var path = base + f;
						if( path == ".tmp" ) continue;
						if( sys.FileSystem.isDirectory(getPath(path)) )
							all.unshift(path);
						else
							all.push(path);
					}
				}
			}
		}
		loop();
	}
}
