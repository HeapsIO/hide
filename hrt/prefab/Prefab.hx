package hrt.prefab;

typedef PrefabField = {
	var name : String;
	var hasSetter : Bool;
	var meta : PrefabMeta;
	var defaultValue : Dynamic;
}

typedef PrefabMeta = {
	var ?doc : String;
	var ?range_min : Float;
	var ?range_max : Float;
	var ?range_step : Float;
}

typedef PrefabInfo = {
	var prefabClass : Class<Prefab>;
	var ?extension: String;
	#if editor
	var inf : hide.prefab.HideProps; 
	#end
};

@:allow(hide)
@:keepSub
@:autoBuild(hrt.prefab.Macros.buildPrefab())
@:build(hrt.prefab.Macros.buildPrefab())
class Prefab {

	/**
		The registered type name for this prefab, used to identify a prefab when serializing
	**/
	public var type(get, never) : String;

	/**
		The name of the prefab in the tree view
	**/
	@:s public var name : String = "";

	/**
		The associated source file (an image, a 3D model, etc.) if the prefab type needs it.
	**/
	@:s public var source : String;

	/**
		The parent of the prefab in the tree view
	**/
	public var children : Array<Prefab> = [];

	/**
		Tells if the prefab will create an instance when calling make() or be ignored. Also apply to this prefab children.
	**/
	@:s public var enabled : Bool = true;

	/**
		Tells if the prefab will create an instance when used in an other prefab or in game. Also apply to this prefab children.
	**/
	@:s public var editorOnly(get, default) : Bool = false;
	function get_editorOnly() {
		if (ignoreEditorOnly)
			return false;
		return editorOnly;
	}
	public static var ignoreEditorOnly = false;

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
	@:s public var props : Any = null;

	/**
		The parent of the prefab in the tree view
	**/
	public var parent(default, set) : Prefab;

	/**
		Infos shared by all the prefabs in a given prefab hierarchy (but not by references)
	**/
	public var shared(default, null) : ContextShared;

	public function new(parent:Prefab, contextShared: ContextShared) {
		if (parent == null) {
			shared = contextShared;
			if (shared == null) {
				shared = new ContextShared(false);
			}
		}
		else
			this.parent = parent;
	}

	function setSharedRec(newShared : ContextShared) {
		this.shared = newShared;
		for (c in children)
			c.setSharedRec(newShared);
	}

	// Accessors
	
	function get_type() {
		var thisClass = Type.getClass(this);
		return getClassTypeName(thisClass);
	}

	function set_parent(p) {
		if( parent != null ) {
			parent.children.remove(this);
		}
		parent = p;
		if( parent != null ) {
			this.shared = parent.shared;
			parent.children.push(this);
		}
		else {
			setSharedRec(new ContextShared(false));
		}
		return p;
	}

	// Lifetime

	#if editor
	public function setEditor(sceneEditor: hide.comp.SceneEditor) {
		if (sceneEditor == null)
			throw "No editor for setEditor";

		shared.editor = sceneEditor;

		setEditorChildren(sceneEditor);
	}

	function setEditorChildren(sceneEditor: hide.comp.SceneEditor) {
		for (c in children) {
			c.setEditorChildren(sceneEditor);
		}
	}
	#end

	// Hierarchical Helpers

	/**
		Find the first h2d.Object in this hierarchy, in either this or it's parents
	**/
	public function findFirstLocal2d() : h2d.Object {
		var o2d = findParent(Object2D, (p) -> p.local2d != null, true);
		return o2d != null ? o2d.local2d : shared.root2d;
	}

	/**
		Find the first h3d.scene.Object in this hierarchy, in either this or it's parents
	**/
	public function findFirstLocal3d() : h3d.scene.Object {
		var o3d = findParent(Object3D, (p) -> p.local3d != null, true);
		return o3d != null ? o3d.local3d : shared.root3d;
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
		Simlar to get() but returns null if not found.
	**/
	public function getOpt<T:Prefab>( cl : Class<T>, ?name : String, ?followRefs : Bool ) : Null<T> {
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
		Returns the root prefab, i.e. the first prefab that doesn't have any parent.
	**/
	public function getRoot( followRefs : Bool = false ) : Prefab {
		var root = this;

		while( root.parent != null || (followRefs && root.shared.parent != null) ) {
			if( root.parent != null )
				root = root.parent;
			else if( followRefs )
				root = root.shared.parent;
		}
		return root;
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
		Returns all the prefab in the tree
	**/
	public function all(?arr: Array<Prefab>) : Array<Prefab> {
		return flatten(Prefab, arr != null ? arr : []);
	}

	/**
		Converts the prefab to another prefab class.
		Returns null if not of this type.
	**/
	public function to<T:Prefab>( c : Class<T> ) : Null<T> {
		return Std.downcast(this, c);
	}

	/**
		Find a the first prefab in the tree with the given class that matches the optionnal `filter`.
		Returns null if no matching prefab was found
	**/
	public function find<T:Prefab>(cl: Class<T>, ?filter : T -> Bool, followRefs : Bool = false ) : Null<T> {
		var asCl = Std.downcast(this, cl);
		if (asCl != null)
			if (filter == null || filter(asCl))
				return asCl;
		for( p in children ) {
			var v = p.find(cl, filter, followRefs);
			if( v != null ) return v;
		}
		return null;
	}

	/**
		Find all the prefabs of the given class `cl` in the tree, that matches `filter` if it is is defined.
		The result is stored in the given array `arr` if it's defined, otherwise an array is created. The final array
		is then returned.
	**/
	public function findAll<T:Prefab>(cl: Class<T>,  ?filter : Prefab -> Bool, followRefs : Bool = false, ?arr : Array<T> ) : Array<T> {
		if( arr == null ) arr = [];
		var asCl = Std.downcast(this, cl);
		if (asCl != null) {
			if (filter == null || filter(asCl))
				arr.push(asCl);
		}
		if (followRefs) {
			var ref = to(Reference);
			if (ref != null && ref.refInstance != null) {
				ref.refInstance.findAll(cl, filter, followRefs, arr);
			}
		}
		for( o in children )
			o.findAll(cl, filter,followRefs,arr);
		return arr;
	}

	/**
		Find the first prefab in this prefab parent chain that matches the given class `cl`, and optionally the given `filter`.
		If `includeSelf` is true, then this prefab is checked as well.
	**/
	public function findParent<T:Prefab>(cl:Class<T> ,?filter : (p:T) -> Bool, includeSelf:Bool = false) : Null<T> {
		var current = includeSelf ? this : this.parent;
		while(current != null) {
			var asCl = Std.downcast(current, cl);
			if (asCl != null) {
				if (filter == null || filter(asCl))
					return asCl;
			}
			current = current.parent;
		}
		return null;
	}

	/**
		Iterate over this children prefab
	**/
	public inline function iterator() : Iterator<Prefab> {
		if (children != null)
			return children.iterator();
		return [].iterator();
	}

	// (Un)Serialization

	/**
		Recursively copy this prefab and it's children into a dynamic object, containing
		all the serializable properties and the type of the object
	**/
	function serialize() : Dynamic {
		var ser = save();
		ser.type = type;

		if (children.length > 0) {
			var serChildren = [];
			for (child in children) {
				serChildren.push(child.serialize());
			}
			ser.children = serChildren;
		}

		return ser;
	}

	/**
		Returns the absolute name path for this prefab
	**/
	public function getAbsPath(unique=false) {
		if(parent == null)
			return "";
		var path = name != null ? name : getDefaultEditorName();
		if(unique) {
			var suffix = 0;
			for(i in 0...parent.children.length) {
				var c = parent.children[i];
				if(c == this)
					break;
				else {
					var cname = c.name != null ? c.name : c.getDefaultEditorName();
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

	#if editor
	// Helpers function for meta
	final function getSerializableProps() : Array<PrefabField> {
		return getSerializablePropsForClass(Type.getClass(this));
	}

	/**
		Returns the default display name for this prefab
	**/
	public function getDefaultEditorName() : String {
		if(source != null) {
			var f = new haxe.io.Path(source).file;
			f = f.split(" ")[0].split("-")[0];
			return f;
		}
		return type.split(".").pop();
	}
	#end

	public function locateObject( path : String ) {
		if( path == null )
			return null;
		var parts = path.split(".");
		var root = shared.root3d;
		while( parts.length > 0 ) {
			var v = null;
			var pname = parts.shift();
			for( o in root )
				if( o.name == pname ) {
					v = o;
					break;
				}
			if( v == null ) {
				v = root.getObjectByName(pname);
				//if( v != null && v.parent != root ) v = null; ??
			}
			if( v == null ) {
				var parts2 = path.split(".");
				for( i in 0...parts.length ) parts2.pop();
				return null;
			}
			root = v;
		}
		return root;
	}

	/**
		If the prefab `props` represent CDB data, returns the sheet name of it, or null.
	 **/
	 public function getCdbType() : String {
		if( props == null )
			return null;
		return Reflect.field(props, "$cdbtype");
	}

	public final function toString() : String{
		var str = type;
		if ( name != "" ) str += '($name)';
		return str;
	}

	/**
		Determines if `child` prefab should be made in the makeChildren() function
	**/
	function shouldMakeChild(child: Prefab) : Bool {
		return child.shouldBeInstanciated();
	}

	function shouldBeInstanciated() : Bool {
		if (!enabled) return false;

		#if editor
		if (shared.parent != null && inGameOnly)
			return false;
		#else
		if (editorOnly)
			return false;
		#end


		return true;
	}

	/**
		Make children is responsible for setting the relevant
		current2d and/or current3d of this prefab so the children
		can create and attach their object to them. Then, makeChild
		can be called on all the children, and current2d/3d must be
		restored to their previous values.
	**/
	function makeChildren() : Void {
		for (c in children) {
			makeChild(c);
		}
	}

	function makeChild(c:Prefab) : Void {
		if (!shouldMakeChild(c)) return;
		if (shared.customMake == null) {
			c.make(shared);
		}
		else {
			shared.customMake(c);
		}
	}

	/**
		Override this function to create runtime objects from this prefab
	**/
	function makeInstance() : Void {
	}

	/**
		Called after makeInstance (and by extension postMakeInstance) has been called on all the children
	**/
	function postMakeInstance() : Void {
	}

	/**
		Allows to customize how an instance gets updated when a property name changes.
		You can also call updateInstance() in order to force whole instance synchronization against current prefab data.
	**/
	public function updateInstance(?propName : String ) {
	}

	/**
		Instanciate this prefab. If `newContextShared` is given or if `this.shared.isInstance` is false,
		this prefab is cloned and then the clone is instanciated and returned.
		If `this.shared.isInstance` is true, this prefab is instanciated instead.
	**/
	public final function make(?shared:ContextShared) : Prefab {
		if (shared == null) {
			shared = this.shared;
		}

		if (!shared.isInstance) {
			shared = new ContextShared(shared.currentPath);
			#if editor
			shared.editor = this.shared.editor;
			#end
			var clone = this.clone(shared);
			return clone.make(shared);
		}

		makeInstanceRec();

		return this;
	}

	function makeInstanceRec() : Void {
		trace(this.toString());

		makeInstance();
		makeChildren();
		postMakeInstance();
	}

	/**
		Create a copy of the data this prefab and all of it's children (unless `withChildren` is `false`), without calling `make()` on them.
		If `parent` is given, then `sh` will be set to `parent.shared`. If `parent` and `sh` is null, `sh` will be set to a new context shared will be created.
		The `parent` and `sh` are then given to the clone constructor.
	**/
	public final function clone(?parent:Prefab = null, ?sh: ContextShared = null, withChildren : Bool = true) : Prefab {
		if (parent != null && sh != null && parent.shared != sh)
			throw "Both parent and sh are set but shared don't match";

		if (sh == null) {
			if (parent != null) {
				sh = parent.shared;
			} else {
				sh = new hrt.prefab.ContextShared(this.shared.currentPath, true);
				#if editor
				sh.editor = shared.editor;
				#end
			}
		}

		var thisClass = Type.getClass(this);

		var inst = Type.createInstance(thisClass, [parent, sh]);
		inst.copy(this);
		if (withChildren) {
			for (child in children) {
				child.clone(inst, sh);
			}
		}

		return inst;
	}

	/**
		Copy all the properties in data to this prefab object. This is not recursive. Done when loading the json data of the prefab.
	**/
	function load(data : Dynamic) : Void {
		this.copyFromDynamic(data);
	}

	/**
		Copy all the properties in Prefab to this prefab object. Done when cloning an existing prefab.
	**/
	function copy(data: Prefab) : Void {
		this.copyFromOther(data);
	}

	/**
		Save all the properties to the given dynamic object. This is not recursive. Returns the updated dynamic object.
	**/
	function save() : Dynamic {
		return this.copyToDynamic({});
	}

	/**
		Cleanup prefab specific ressources, and call dispose on it's children.
	**/
	public function dispose() {
		for (child in children) {
			child.dispose();
		}
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
				newchild.push(createFromDynamic(v,this));
			}
		}
		children = newchild;
	}


#if editor
	
	// Editor API

	/**
		Allows to customize how the prefab object is displayed / handled within Hide
	**/
	public function getHideProps() : hide.prefab.HideProps {
		return { icon : "question-circle", name : "Unknown" };
	}

	/**
		Create an interactive object to the scene objects of this prefab
	**/
	public function makeInteractive() : hxd.SceneEvents.Interactive {
		return null;
	}

	/**
		Allows to customize how the prefab instance changes when selected/unselected within Hide.
		Selection of descendants is skipped if false is returned.
	**/
	public function setSelected(b : Bool ) : Bool {
		return true;
	}

	/**
		Called when the hide editor wants to edit this Prefab.
		Used to create the various editor interfaces
	**/
	public function edit(editContext : hide.prefab.EditContext) {
	}
#end

	/**
		Create a new prefab from the given `data`.
	**/
	public static function createFromDynamic(data:Dynamic, parent:Prefab = null, contextShared:ContextShared = null) : Prefab {
		var type : String = data.type;

		var cl : Class<Prefab> = Unknown;

		if (type != null) {
			var classEntry = registry.get(type);
			if (classEntry != null)
				cl = classEntry.prefabClass;
		}

		var prefabInstance = Type.createInstance(cl, [parent, contextShared]);

		prefabInstance.load(data);

		var children = Std.downcast(Reflect.field(data, "children"), Array);
		if (children != null) {
			for (child in children) {
				createFromDynamic(child, prefabInstance);
			}
		}

		return prefabInstance;
	}

	/**
		Check if `original` prefab class is or inherits for the class `parent`.
	**/
	public static function isOfType( original : Class<Prefab>, parent : Class<Prefab> ) {
		var c : Class<Dynamic> = original;
		while( c != null ) {
			if( c == parent ) return true;
			c = Type.getSuperClass(c);
		}
		return false;
	}

	inline static function getSerializablePropsForClass(cl : Class<Prefab>) {
		return (cl:Dynamic).getSerializablePropsStatic();
	}

	public static function getClassTypeName(cl : Class<Prefab>) : String {
		return reverseRegistry.get(Type.getClassName(cl));
	}

	public static function getPrefabInfoByName(name:String) : PrefabInfo {
		return registry[name];
	}

	static var registry : Map<String, PrefabInfo> = new Map();

	// Map prefab class name to the serialized name of the prefab
	static var reverseRegistry : Map<String, String> = new Map();
	static var extensionRegistry : Map<String, String> = new Map();

	/**
		Register the given prefab class with the given typeName in the prefab regsitry.
		This is necessary for the serialisation system.
		Call it by placing this in you prefab class :
		```
		public static var _ = Prefab.register("myPrefabName", myPrefabClassName);
		```
	**/
	static function register(typeName : String, prefabClass: Class<hrt.prefab.Prefab>, ?extension: String) {
		#if editor
		var info : hide.prefab.HideProps = cast Type.createEmptyInstance(prefabClass).getHideProps();
		#end

		reverseRegistry.set(Type.getClassName(prefabClass), typeName);
		registry.set(typeName, {prefabClass: prefabClass #if editor, inf : info #end, extension: extension});
		if (extension != null) {
			extensionRegistry.set(extension, typeName);
		}

		return true;
	}

	public static function getPrefabType(path: String) {
		var extension = path.split(".").pop().toLowerCase();
		return extensionRegistry.get(extension);
	}

	/**
		Return the first h3d.scene.Objects found in each of this prefab children.
		If a children has no h3d.scene.Objects, it then search in it's children and so on.
	**/
	static function getChildrenRoots( base : h3d.scene.Object, p : Prefab, out : Array<h3d.scene.Object> ) {
		for( c in p.children ) {
			var local3d = Object3D.getLocal3d(c);
			if( local3d == base )
				getChildrenRoots(base, c, out);
			else
				out.push(local3d);
		}
		return out;
	}

	// Static initialization trick to register this class with the given name
	// in the prefab registry. Call this in your own classes
	public static var _ = Prefab.register("prefab", Prefab, "prefab");
}
