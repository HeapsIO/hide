package hrt.prefab;

/**
	Prefab is an data-oriented tree container capable of creating instances of Heaps objects.
**/
@:keepSub @:build(hrt.impl.Macros.buildPrefab()) @:autoBuild(hrt.impl.Macros.buildPrefab())
class Prefab {

	/**
		The type of prefab, allows to identify which class it should be loaded with.
	**/
	@:s public var type(default, null) : String;

	/**
		The name of the prefab in the tree view
	**/
	@:s public var name : String;

	/**
		The parent of the prefab in the tree view
	**/
	public var parent(default, set) : Prefab;

	/**
		The associated source file (an image, a 3D model, etc.) if the prefab type needs it.
	**/
	@:s public var source : String;

	/**
		The list of children prefab in the tree view
	**/
	public var children(default, null) : Array<Prefab>;

	/**
		Tells if the prefab will create an instance when calling make() or be ignored. Also apply to this prefab children.
	**/
	@:s public var enabled : Bool = true;

	/**
		Tells if the prefab will create an instance when used in an other prefab or in game. Also apply to this prefab children.
	**/
	@:s public var editorOnly : Bool = false;

	/**
		Tells if the prefab will create an instance when used in editor. Also apply to this prefab children.
	**/
	@:s public var inGameOnly : Bool = false;

	/**
		Prevent the prefab from being selected in Hide. Also apply to this prefab children.
	**/
	@:s public var locked : Bool = false;

	/**
		A storage for some extra properties
	**/
	@:s public var props : Any;

	/**
		Creates a new prefab with the given parent.
	**/
	public function new(?parent : Prefab) {
		this.parent = parent;
		children = [];
	}

	function set_parent(p) {
		if( parent != null )
			parent.children.remove(this);
		parent = p;
		if( parent != null )
			parent.children.push(this);
		return p;
	}

	#if editor

	/**
		Allows to customize how the prefab object is edited within Hide
	**/
	public function edit( ctx : hide.prefab.EditContext ) {
	}

	/**
		Allows to customize how the prefab object is displayed / handled within Hide
	**/
	public function getHideProps() : hide.prefab.HideProps {
		return { icon : "question-circle", name : "Unknown" };
	}

	/**
		Allows to customize how the prefab instance changes when selected/unselected within Hide.
		Selection of descendants is skipped if false is returned.
	**/
	public function setSelected( ctx : Context, b : Bool ) {
		return true;
	}

	/**
		Allows the prefab to create an interactive so it can be selected in the scene.
	**/
	public function makeInteractive( ctx : Context ) : hxd.SceneEvents.Interactive {
		return null;
	}

	#end

	/**
		Iterate over children prefab
	**/
	public inline function iterator() : Iterator<Prefab> {
		return children.iterator();
	}

	/**
		Override to implement your custom prefab data loading
	**/
	function load( obj : Dynamic ) {
		loadSerializedFields(obj);
	}

	/**
		Override to implement your custom prefab data saving
	**/
	function save() : {} {
		var obj = {};
		saveSerializedFields(obj);
		return obj;
	}

	/**
		Override to implement your custom prefab data copying.
		You should copy the field from `p` to `this`, p being an instance of your class
	**/
	function copy( p : Prefab ) {
		copySerializedFields(p);
	}

	function copyValue<T>( v : T ) : T {
		// copy in-depth - might be optimized by macros when called in copy()
		return haxe.Unserializer.run(haxe.Serializer.run(v));
	}

	/**
		Creates an instance for this prefab only (and not its children).
		Use make(ctx) to creates the whole instances tree;
	**/
	public function makeInstance( ctx : Context ) : Context {
		return ctx;
	}

	/**
		Allows to customize how an instance gets updated when a property name changes.
		You can also call updateInstance(ctx) in order to force whole instance synchronization against current prefab data.
	**/
	public function updateInstance( ctx : Context, ?propName : String ) {
	}

	/**
		Removes the created instance for this prefab only (not is children).
		If false is returned, the instance could not be removed and the whole context scene needs to be rebuilt
	**/
	public function removeInstance( ctx : Context ) : Bool {
		return false;
	}

	/**
		Save the whole prefab data and its children.
	**/
	public final function saveData() : {} {
		var obj : Dynamic = save();

		if( children.length > 0 )
			obj.children = [for( s in children ) s.saveData()];
		
		return obj;
	}

	/**
		Load the whole prefab data and creates its children.
	**/
	public final function loadData( v : Dynamic ) {
		load(v);
		if( children.length > 0 )
			children = [];
		var children : Array<Dynamic> = v.children;
		if( children != null )
			for( v in children )
				loadPrefab(v, this);
	}

	/**
		Updates in-place the whole prefab data and its children.
	**/
	public function reload( p : Dynamic ) {
		var prevProps = props;
		load(p);

		if( props != null && prevProps != null ) {
			// update prev props object instead of rebinding it : allow to propagate cdb changes
			var old = Reflect.fields(prevProps);
			for( k in Reflect.fields(props) ) {
				if( haxe.Json.stringify(Reflect.field(props,k)) == haxe.Json.stringify(Reflect.field(prevProps,k)) ) {
					old.remove(k);
					continue;
				}
				Reflect.setField(prevProps, k, Reflect.field(props,k));
				old.remove(k);
			}
			for( k in old )
				Reflect.deleteField(prevProps, k);
			props = prevProps;
		}

		var childData : Array<Dynamic> = p.children;
		if( childData == null ) {
			if( this.children.length > 0 ) this.children = [];
			return;
		}
		var curChild = new Map();
		for( c in children ) {
			var cl = curChild.get(c.name);
			if( cl == null ) {
				cl = [];
				curChild.set(c.name, cl);
			}
			cl.push(c);
		}
		var newchild = [];
		for( v in childData ) {
			var name : String = v.name;
			var cl = curChild.get(name);
			var prev = null;
			if( cl != null ) {
				for( c in cl )
					if( c.type == v.type ) {
						prev = c;
						cl.remove(prev);
						break;
					}
			}
			if( prev != null ) {
				prev.reload(v);
				newchild.push(prev);
			} else {
				newchild.push(loadPrefab(v,this));
			}
		}
		children = newchild;
	}

	/**
		Creates the correct prefab based on v.type and load its data and children.
		If one the prefab in the tree is not registered, a hxd.prefab.Unkown is created instead.
	**/
	public static function loadPrefab( v : Dynamic, ?parent : Prefab ) {
		var pcl = @:privateAccess Library.registeredElements.get(v.type);
		var pcl = pcl == null ? null : pcl.cl;
		if( pcl == null ) pcl = Unknown;
		var p = Type.createInstance(pcl, [parent]);
		p.loadData(v);
		return p;
	}

	/**
		Creates an instance for this prefab and its children.
	**/
	public function make( ctx : Context ) : Context {
		if( !enabled )
			return ctx;
		if( ctx == null ) {
			ctx = new Context();
			ctx.init();
		}
		var fromRef = #if editor ctx.shared.parent != null #else true #end;
		if (fromRef && editorOnly #if editor || inGameOnly #end)
			return ctx;
		ctx = makeInstance(ctx);
		for( c in children )
			makeChild(ctx, c);
		return ctx;
	}

	function makeChild( ctx : Context, p : Prefab ) {
		if( ctx.shared.customMake == null )
			p.make(ctx);
		else if( p.enabled )
			ctx.shared.customMake(ctx, p);
	}

	/**
	 	If the prefab `props` represent CDB data, returns the sheet name of it, or null.
	 **/
	public function getCdbType() : String {
		if( props == null )
			return null;
		return Reflect.field(props, "$cdbtype");
	}

	/**
		Search the prefab tree for the prefab matching the given name, returns null if not found
	**/
	public function getPrefabByName( name : String ) {
		if( this.name == name )
			return this;
		for( c in children ) {
			var p = c.getPrefabByName(name);
			if( p != null )
				return p;
		}
		return null;
	}

	/**
		Search the prefab tree for the prefabs matching the given path.
		Can use wildcards, such as `*`/level`*`/collision
	**/
	public function getPrefabsByPath( path : String ) {
		var out = [];
		if( path == "" )
			out.push(this);
		else
			getPrefabsByPathRec(path.split("."), 0, out);
		return out;
	}

	function getPrefabsByPathRec( parts : Array<String>, index : Int, out : Array<Prefab> ) {
		var name = parts[index++];
		if( name == null ) {
			out.push(this);
			return;
		}
		var r = name.indexOf('*') < 0 ? null : new EReg("^"+name.split("*").join(".*")+"$","");
		for( c in children ) {
			var cname = c.name;
			if( cname == null ) cname = c.getDefaultName();
			if( r == null ? c.name == name : r.match(cname) )
				c.getPrefabsByPathRec(parts, index, out);
		}
	}

	/**
		Simlar to get() but returns null if not found.
	**/
	public function getOpt<T:Prefab>( cl : Class<T>, ?name : String, ?followRefs : Bool ) : T {
		if( name == null || this.name == name ) {
			var cval = to(cl);
			if( cval != null ) return cval;
		}
		for( c in children ) {
			var p = c.getOpt(cl, name, followRefs);
			if( p != null )
				return p;
		}
		return null;
	}

	/**
		Search the prefab tree for the prefab matching the given prefab class (and name, if specified).
		Throw an exception if not found. Uses getOpt() to return null instead.
	**/
	public function get<T:Prefab>( cl : Class<T>, ?name : String ) : T {
		var v = getOpt(cl, name);
		if( v == null )
			throw "Missing prefab " + (name == null ? Type.getClassName(cl) : (cl == null ? name : name+"(" + Type.getClassName(cl) + ")"));
		return v;
	}

	/**
		Return all prefabs in the tree matching the given prefab class.
	**/
	public function getAll<T:Prefab>( cl : Class<T>, ?followRefs : Bool, ?arr: Array<T> ) : Array<T> {
		return findAll(function(p) return p.to(cl), followRefs, arr);
	}

	/**
		Find a single prefab in the tree by calling `f` on each and returning the first not-null value returned, or null if not found.
	**/
	public function find<T>( f : Prefab -> Null<T>, ?followRefs : Bool ) : Null<T> {
		var v = f(this);
		if( v != null )
			return v;
		for( p in children ) {
			var v = p.find(f, followRefs);
			if( v != null ) return v;
		}
		return null;
	}

	/**
		Find several prefabs in the tree by calling `f` on each and returning all the not-null values returned.
	**/
	public function findAll<T>( f : Prefab -> Null<T>, ?followRefs : Bool, ?arr : Array<T> ) : Array<T> {
		if( arr == null ) arr = [];
		var v = f(this);
		if( v != null )
			arr.push(v);
		for( o in children )
			o.findAll(f,followRefs,arr);
		return arr;
	}

	/**
		Returns all prefabs in the tree matching the specified class.
	**/
	public function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		if(arr == null)
			arr = [];
		if( cl == null )
			arr.push(cast this);
		else {
			var i = to(cl);
			if(i != null)
				arr.push(i);
		}
		for(c in children)
			c.flatten(cl, arr);
		return arr;
	}

	/**
		Returns the first parent in the tree matching the specified class or null if not found.
	**/
	public function getParent<T:Prefab>( c : Class<T> ) : Null<T> {
		var p = parent;
		while(p != null) {
			var inst = p.to(c);
			if(inst != null) return inst;
			p = p.parent;
		}
		return null;
	}

	/**
		Converts the prefab to another prefab class.
		Returns null if not of this type.
	**/
	public function to<T:Prefab>( c : Class<T> ) : Null<T> {
		return Std.downcast(this, c);
	}

	/**
		Returns the absolute name path for this prefab
	**/
	public function getAbsPath(unique=false) {
		if(parent == null)
			return "";
		var path = name != null ? name : getDefaultName();
		if(unique) {
			var suffix = 0;
			for(i in 0...parent.children.length) {
				var c = parent.children[i];
				if(c == this)
					break;
				else {
					var cname = c.name != null ? c.name : c.getDefaultName();
					if(cname == path)
						++suffix;
				}
			}
			if(suffix > 0)
				path += "-" + suffix;
		}
		if(parent.parent != null)
			path = parent.getAbsPath(unique) + "." + path;
		return path;
	}

	/**
		Returns the default name for this prefab
	**/
	public function getDefaultName() : String {
		if(source != null) {
			var f = new haxe.io.Path(source).file;
			f = f.split(" ")[0].split("-")[0];
			return f;
		}
		return type.split(".").pop();
	}

	/**
		Clone this prefab, and all its children if recursive=true.
	**/
	public final function clone( ?parent : Prefab, recursive = true ) : Prefab {
		var obj = Type.createInstance(Type.getClass(this),[parent]);
		obj.copy(this);
		if( recursive ) {
			for( c in children )
				c.clone(obj);
		}
		return obj;
	}

	/**
		Similar to clone() but uses full data copying to guarantee a whole copy with no data reference (but is slower).
	**/
	public final function cloneData( recursive = true ) {
		var data = recursive ? saveData() : save();
		data = haxe.Json.parse(haxe.Json.stringify(data));
		return loadPrefab(data);
	}
}
