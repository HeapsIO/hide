package hrt.prefab;

/**
	Prefab is an data-oriented tree container capable of creating instances of Heaps objects.
**/
@:keepSub
class Prefab {

	/**
		The type of prefab, allows to identify which class it should be loaded with.
	**/
	public var type(default, null) : String;

	/**
		The name of the prefab in the tree view
	**/
	public var name(default, set) : String;

	/**
		The parent of the prefab in the tree view
	**/
	public var parent(default, set) : Prefab;

	/**
		The associated source file (an image, a 3D model, etc.) if the prefab type needs it.
	**/
	public var source(default, set) : String;

	/**
		The list of children prefab in the tree view
	**/
	public var children(default, null) : Array<Prefab>;

	/**
		Tells if the prefab will create an instance when calling make() or be ignored. Also apply to this prefab children.
	**/
	public var enabled : Bool = true;


	/**
		A storage for some extra properties
	**/
	public var props : Any;

	/**
		Creates a new prefab with the given parent.
	**/
	public function new(?parent) {
		this.parent = parent;
		children = [];
	}

	function set_name(n) {
		return name = n;
	}

	function set_source(f) {
		return source = f;
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
	function load( v : Dynamic ) {

	}

	/**
		Override to implement your custom prefab data saving
	**/
	function save() : {} {
		return {};
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
	@:final public function saveData() : {} {
		var obj : Dynamic = save();
		obj.type = type;
		if( !enabled )
			obj.enabled = false;
		if( name != null )
			obj.name = name;
		if( source != null )
			obj.source = source;
		if( children.length > 0 )
			obj.children = [for( s in children ) s.saveData()];
		if( props != null && obj.props == null )
			obj.props = props;
		return obj;
	}

	/**
		Load the whole prefab data and creates its children.
	**/
	@:final public function loadData( v : Dynamic ) {
		type = v.type;
		name = v.name;
		enabled = v.enabled == null ? true : v.enabled;
		props = v.props;
		source = v.source;
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
		name = p.name;
		enabled = p.enabled == null ? true : p.enabled;
		if( p.props == null || props == null )
			props = p.props;
		else {
			var old = Reflect.fields(props);
			for( k in Reflect.fields(p.props) ) {
				if( haxe.Json.stringify(Reflect.field(props,k)) == haxe.Json.stringify(Reflect.field(p.props,k)) ) {
					old.remove(k);
					continue;
				}
				Reflect.setField(props, k, Reflect.field(p.props,k));
				old.remove(k);
			}
			for( k in old )
				Reflect.deleteField(props, k);
		}
		source = p.source;
		load(p);
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
		ctx = makeInstance(ctx);
		for( c in children )
			makeChildren(ctx, c);
		return ctx;
	}

	function makeChildren( ctx : Context, p : Prefab ) {
		if( ctx.shared.customMake == null )
			p.make(ctx);
		else
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
	public function getOpt<T:Prefab>( cl : Class<T>, ?name : String ) : T {
		if( name == null || this.name == name ) {
			var cval = to(cl);
			if( cval != null ) return cval;
		}
		for( c in children ) {
			var p = c.getOpt(cl, name);
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
	public function getAll<T:Prefab>( cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		return findAll(function(p) return p.to(cl));
	}

	/**
		Find a single prefab in the tree by calling `f` on each and returning the first not-null value returned, or null if not found.
	**/
	public function find<T>( f : Prefab -> Null<T> ) : Null<T> {
		var v = f(this);
		if( v != null )
			return v;
		for( p in children ) {
			var v = p.find(f);
			if( v != null ) return v;
		}
		return null;
	}

	/**
		Find several prefabs in the tree by calling `f` on each and returning all the not-null values returned.
	**/
	public function findAll<T>( f : Prefab -> Null<T>, ?arr : Array<T> ) : Array<T> {
		if( arr == null ) arr = [];
		var v = f(this);
		if( v != null )
			arr.push(v);
		for( o in children )
			o.findAll(f,arr);
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
	public function getAbsPath() {
		var p = this;
		var path = [];
		while(p.parent != null) {
			var n = p.name;
			if( n == null ) n = getDefaultName();
			path.unshift(n);
			p = p.parent;
		}
		return path.join('.');
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
		Clone this prefab and all its children
	**/
	public function clone() : Prefab {
		var obj = saveData();
		return loadPrefab(haxe.Json.parse(haxe.Json.stringify(obj)));
	}
}
