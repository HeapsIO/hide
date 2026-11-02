package hide.tools;

#if !macro
/**
	View for a String -> Any dictionary, get/set functions retrieves or stores the data either in
	this.store, or in parent.store[key] if parent is set.

	Usage :

	- Store state globally :
		Use hide.Ide.inst.globalState for user state that is cross project, or hide.Ide.inst.projectState for
		project specific state.
		Calling set/get saves the values at the root of these configs objects (they will be serialized at the root of their respective editorState.json files)
	- Nesting state :
		For scoped state, or objects that can optionally store their state (for example FancyArray open state can be optionally stored),
		create a new public EditorState object inside the class, and store your state using the get/set api.
		Then the user of your class can call editorState.setParent(parentState, "key") to store the child state inside parentState under the "key"
		entry. Note that state stored before setParent is called is lost, so don't get/set state as part of your object constructor.
		For convenience, Views create their own global / projectState that are stored inside views."view.class.path", and FileView exposes
		a fileState that is saved inside files."file/path"."view.class.path".

	- Macros :
		Member variables of a class can be saved into a state using the @:state variable annotation.
		For the moment only value types are covered by this macro, and must have a default value.
		To use it, first add @:build(hide.tools.EditorState.build()) to your class, then you can use
		the annotation `@:state(state_variable)` to transform the variable into a getter/setter pair that
		store its value into an EditorState named `state_variable`.
		The default value will be used when the key is not set, and if someone sets the variable to its
		default value, it will be removed from the state.

		Example :
		```haxe
		var localState = new EditorState(); // first we need a state object to store our variable.
											// Note that until setParent is called, the state is stored
											// won't be saved on disk

		@:state(localState) var localTransform : Bool = false; // reads and writes to localTransform
															   // use localState.get/set("localTransform");
		```
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

	// called when data changes happens inside the tree
	function change() {
		parent?.change();
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
		change();
	}

	public function remove(k) {
		var store = store ?? parent.get(key);
		if (store == null)
			return;
		Reflect.deleteField(store, k);
		if (parent != null && Reflect.fields(store).length == 0) {
			parent.remove(key);
		}
		change();
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

/**
	EditorState that stores its state as a file on disk
**/
class EditorStateRoot extends EditorState {
	var saveDelay: haxe.Timer;

	public function new(filePath: String) {
		super(null, filePath);
		load(filePath);
	}

	override function setParent(p, path) {
		if (p != null)
			throw "EditorStateRoot can't have a parent";
		super.setParent(p, path);
	}

	static final saveDebounce = 1_000;

	override function change() {
		queueSave();
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
				if( !isValueType(haxe.macro.Context.resolveType(t, f.pos)) )
					haxe.macro.Context.error("@:state only supports Bool, Int, Float and String", f.pos);
				if( def == null )
					haxe.macro.Context.error("@:state expects a default value", f.pos);
				f.kind = FProp("get", "set", t);

				fields.push({
					name : "get_" + key,
					pos : f.pos,
					kind : FFun({ args : [], ret : t, expr : macro return $state.get($v{key}, $def) }),
				});
				fields.push({
					name : "set_" + key,
					pos : f.pos,
					kind : FFun({ args : [{ name : "v", type : t }], ret : t, expr : macro { if( v == $def ) $state.remove($v{key}) else $state.set($v{key}, v); return v; } }),
				});
			default:
				haxe.macro.Context.error("@:state expects a var with an explicit type", f.pos);
			}
		}
		return fields;
	}

	static function isValueType( t : haxe.macro.Type ) {
		return switch( haxe.macro.Context.follow(t) ) {
		case TAbstract(_.get() => { pack : [], name : "Null" }, [p]): isValueType(p);
		case TAbstract(_.get() => { pack : [], name : "Bool" | "Int" | "Float" }, _): true;
		case TInst(_.get() => { pack : [], name : "String" }, _): true;
		default: false;
		}
	}
}
#end