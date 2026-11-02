package hide.tools;

/**
	View for a String -> Any dictionary, that get/set values either in
	itself, or in parent[key] if parent is set.

	Usage :

	- Store state globally :
		Use ide.Inst.globalState for user state that is cross project, or ide.Inst.projectState for
		project specific state.
		Calling set/get saves the values at the root of these config (at the root of editorState.json)
	- Nesting state :
		For scoped state, or objects that can optionally store their state (for example FancyArray open state can be optionnaly stored),
		create a new public EditorState object inside the class, and store your state using the get/set api.
		Then the user of your class can call editorState.setParent(parentState, "key") to store the child state inside parentState unde the "key"
		entry. Note that state stored before setParent is called is lost, so don't get/set state as part of your object constructor.
		For convenience, Views create their own global / projectState that are stored inside views."view.class.path", and FileView expose
		a fileState that is saved inside files."file/path"."view.class.path".

**/
class EditorState {
	// Key of this state in its parent object
	public var key(default, null): String;

	public var parent(default, null) : EditorState;
	// only a State without a parent has a store, other uses parent.get(k)
	var store : Dynamic;

	// note : caching store is really hard :
	// a store is only valid for a given tree state,
	// if a parent changes, all of its children need
	// to know. We can't just store children in a Map<String, EditorState> because it's perfectly legal to have two EditorState pointing
	// to the same path (they point to the same data)
	// More so, if children register in their parent, they now have to unregister themselves or
	// or else they will leak. So no cache.
	// A nested Map<String, Map<String, V>> access is around 5x faster than concatenating keys,
	// so for replacing the old saveDisplayState("value"), we are faster without the cache as long
	// as the depth is less than 5, which in practice should be the case.

	public function new(?parent: EditorState, ?key: String) {
		setParent(parent, key);
	}

	public function setParent(parent: EditorState, key: String) {
		this.parent = parent;
		this.key = key;
		if (parent != null) {
			store = null;
		} else {
			store = {};
		}
	}

	public function get(k, ?def) : Any {
		var store = store ?? parent.get(key);
		if (store == null)
			return def;
		return Reflect.field(store, k) ?? def;
	}

	public function set(k, v) {
		var store = store ?? parent.getInit(key);
		Reflect.setField(store, k, v);
	}

	public function remove(k) {
		var store = store ?? parent.get(key);
		if (store == null)
			return;
		Reflect.deleteField(store, k);
		if (parent != null && Reflect.fields(store).length == 0) {
			parent.remove(key);
		}
	}

	function getInit(k) : Dynamic {
		var store = store ?? parent.getInit(key);
		var v = Reflect.field(store, k);
		if (v == null) {
			v = {};
			Reflect.setField(store, k, v);
		}
		return v;
	}
}
class EditorStateRoot extends EditorState {
	var saveDelay: haxe.Timer;

	public function new(filePath: String) {
		super(null, filePath);
		load(filePath);
	}

	static final saveDebounce = 1_000;

	// called when a child calls set();
	override function getInit(k) : Dynamic {
		queueSave();
		return super.getInit(k);
	}

	override function set(k, v) {
		queueSave();
		super.set(k,v);
	}

	function queueSave() {
		if (saveDelay != null) {
			saveDelay.stop();
		}
		saveDelay = haxe.Timer.delay(() -> save(), saveDebounce);
	}

	public function load(filePath) {
		key = filePath;
		if (key != null) {
			try {
				store = haxe.Json.parse(sys.io.File.getContent(key));
			} catch( e : Dynamic ) {
				store = {};
				trace('Invalid editor state $key, it will be reset ($e)');
			}
		} else {
			store = {};
		}
	}

	public function save() {
		if( hide.Ide.inst.readOnlyConfig || key == null )
			return;
		var dir = haxe.io.Path.directory(key);
		if( !sys.FileSystem.exists(dir) )
			sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(key, haxe.Json.stringify(store ?? {}, null, "\t"));
	}
}