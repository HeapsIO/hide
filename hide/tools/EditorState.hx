package hide.tools;

class EditorState {

	#if editor_hl
	static final SAVE_DELAY = 5.0;
	static var pendingSaves : Array<EditorState> = [];
	var saveDelay = 0.0;
	#end

	public var path(default, null) : Null<String>; // File where the state is saved, null for a state only kept in memory
	var data : Dynamic = {};

	public function new( ?path : String ) {
		this.path = path;
		if( path != null && sys.FileSystem.exists(path) ) {
			try {
				data = haxe.Json.parse(sys.io.File.getContent(path));
			} catch( e : Dynamic ) {
				trace('Invalid editor state $path, it will be reset ($e)');
			}
		}
	}

	public function get( key : String, ?defaultVal : Dynamic ) : Dynamic {
		var v = Reflect.field(data, key);
		return v != null ? v : defaultVal;
	}

	public function set( key : String, value : Dynamic ) {
		Reflect.setField(data, key, value);
		queueSave();
	}

	public function remove( key : String ) {
		Reflect.deleteField(data, key);
		queueSave();
	}

	function queueSave() {
		if( path == null )
			return;
		#if editor_hl
		if( !pendingSaves.contains(this) ) {
			saveDelay = SAVE_DELAY;
			pendingSaves.push(this);
		}
		#else
		saveToDisk();
		#end
	}

	function saveToDisk() {
		if( hide.Ide.inst.readOnlyConfig )
			return;
		var dir = haxe.io.Path.directory(path);
		if( !sys.FileSystem.exists(dir) )
			sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(path, haxe.Json.stringify(data, null, "\t"));
	}

	#if editor_hl
	public static function updatePendingSaves( dt : Float ) {
		var i = pendingSaves.length;
		while( i-- > 0 ) {
			var state = pendingSaves[i];
			state.saveDelay -= dt;
			if( state.saveDelay <= 0 ) {
				pendingSaves.splice(i, 1);
				state.saveToDisk();
			}
		}
	}

	public static function flushPendingSaves() {
		var states = pendingSaves;
		pendingSaves = [];
		for( state in states )
			state.saveToDisk();
	}
	#end
}
