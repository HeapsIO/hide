package hide.tools;

#if !macro
/**
	Tree of values saved on disk. A child state is a proxy to a subtree of its parent's data,
	its changes are saved by the root state.
**/
class EditorState {

	#if editor_hl
	static final SAVE_DELAY = 5.0;
	static var pendingSaves : Array<EditorState> = [];
	var saveDelay = 0.0;
	#end

	public var path(default, null) : Null<String>; // File where the state is saved, null for a state only kept in memory
	var key: String;
	var parent : EditorState;
	var children : Map<String, EditorState> = [];
	var attached : Bool; // data is a subtree of a root state's data
	var data : Dynamic = {};

	public function new( ?path : String, isRoot = false ) {
		this.path = path;
		attached = isRoot;
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

	/**
		Replaces the data of this state by the `key` subtree of `parent`.
	**/
	public function setParent( parent : EditorState, key : String ) {
		attach(parent, key);
	}

	/**
		Stores this state in `globalState.views[key]`.
	**/
	public function initGlobalView( key : String ) {
		attach(hide.Ide.inst.globalViewState, key);
	}

	/**
		Stores this state in `projectState.views[key]`.
	**/
	public function initLocalView( key : String ) {
		attach(hide.Ide.inst.projectViewState, key);
	}

	/**
		Stores this state in `projectState.files[file][view]`.
	**/
	public function initFileView( file : String, view : String ) {
		return hide.Ide.inst.projectFileState.getOrInitState(view);
	}

	public function getOrInitState(key: String) {
		var childState = children.get(key);
		if (childState == null) {
			childState = new EditorState(null, false);
			childState.setParent(this, key);
		}
		return childState;
	}

	function attach( parent : EditorState, key : String ) {
		if( this.parent != null || path != null )
			throw "can't reparent states";
		this.parent = parent;
		this.key = key;
		parent.children.set(key, this);

		function bind( state : EditorState ) {
			state.attached = true;
			state.data = Reflect.field(state.parent.data, key);
			if (state.data == null) {
				state.data = {};
				Reflect.setField(state.parent.data, state.key, state.data);
			}
			for( c in state.children )
				bind(c);
		}

		if( parent.attached )
			bind(this);
	}

	function queueSave() {
		if( parent != null ) {
			parent.queueSave();
			return;
		}
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

		// copy without empty objects : data is shared with the child states
		function removeEmpty( v : Dynamic ) : Dynamic {
			if( Type.typeof(v) != TObject )
				return v;
			var out = {};
			for( f in Reflect.fields(v) ) {
				var c = removeEmpty(Reflect.field(v, f));
				if( c != null )
					Reflect.setField(out, f, c);
			}
			return Reflect.fields(out).length == 0 ? null : out;
		}

		sys.io.File.saveContent(path, haxe.Json.stringify(removeEmpty(data) ?? {}, null, "\t"));
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
#else
class EditorState {

	/**
		Turns each `@:state(state) var name : T = default` into a property stored in `state` under the key `name`.
	**/
	public static function build() : Array<haxe.macro.Expr.Field> {
		var fields = haxe.macro.Context.getBuildFields();
		for( f in fields.copy() ) {
			var meta = Lambda.find(f.meta, m -> m.name == ":state");
			if( meta == null )
				continue;
			if( meta.params.length != 1 )
				haxe.macro.Context.error("@:state expects the state as parameter", meta.pos);

			var state = meta.params[0];
			var key = f.name;
			switch( f.kind ) {
			case FVar(t, def) if( t != null ):
				if( def == null )
					def = macro null;
				f.kind = FProp("get", "set", t);
				fields.push({
					name : "get_" + key,
					pos : f.pos,
					kind : FFun({ args : [], ret : t, expr : macro return $state.get($v{key}, $def) }),
				});
				fields.push({
					name : "set_" + key,
					pos : f.pos,
					kind : FFun({ args : [{ name : "v", type : t }], ret : t, expr : macro { $state.set($v{key}, v); return v; } }),
				});
			default:
				haxe.macro.Context.error("@:state expects a var with an explicit type", f.pos);
			}
		}
		return fields;
	}
}
#end
