package hrt.prefab;

typedef PrefabField = {
	var name : String;
	var hasSetter : Bool;
	var meta : PrefabMeta;
	var defaultValue : Dynamic;
	var type : Macros.PrefabFieldType;
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

@:access(Prefab)
abstract ContextMake(ContextShared) from ContextShared to ContextShared {

	@:from static function fromObject3D( parent : h3d.scene.Object ) : ContextMake {
		return new ContextShared(parent, true);
	}

	@:from static function fromObject2D( parent : h2d.Object ) : ContextMake {
		return new ContextShared(parent, true);
	}
}

#if editor
enum TreeChangedResult {
	Skip; /**Don't rebuild this prefab**/
	Rebuild; /** Force rebuild this prefab **/
	Notify(callback: Void -> Void); /**Call the callback once all the prefab that wanted rebuild have been rebuild. Call order betwteen multiple Notify are not guaranteed. Only one callback will be called by prefab in the tree**/
}
#end

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
	public static var emptyNameReplacement = "$no_name";

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
	@:s public var editorOnly : Bool = false;
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

	// Public API

	public function new(parent:Prefab, contextShared: ContextShared) {
		initParentShared(parent, contextShared);
	}

	function initParentShared(parent:Prefab, contextShared: ContextShared) {
		if (parent == null) {
			shared = contextShared;
			if (shared == null) {
				shared = new ContextShared(false);
			}
		}
		else
			this.parent = parent;
	}

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
			setSharedRec(parent.shared);
			parent.children.push(this);
		}
		else {
			setSharedRec(new ContextShared(false));
		}
		return p;
	}

	/**
		Instanciate this prefab. If `newContextShared` is given or if `this.shared.isInstance` is false,
		this prefab is cloned and then the clone is instanciated and returned.
		If `this.shared.isInstance` is true, this prefab is instanciated instead.
	**/
	public function make( ?sh:ContextMake ) : Prefab {
		// -- There is generated code here to properly clone the prefab if sh is set. See hrt.prefab.Macros
		if (!shouldBeInstanciated())
			return this;

		makeInstance();
		for (c in children)
			makeChild(c);
		postMakeInstance();

		return this;
	}

	function makeClone(?sh:ContextShared) : Prefab {
		if( sh == null ) {
			sh = new ContextShared(shared.currentPath);
		}
		if( !sh.isInstance ) throw "assert";
		if( sh.currentPath == null ) sh.currentPath = shared.currentPath;
		#if editor
		sh.editor = this.shared.editor;
		sh.scene = this.shared.scene;
		#end
		return this.clone(sh).make(sh);
	}

	/**
		Create a copy of the data this prefab and all of it's children (unless `withChildren` is `false`), without calling `make()` on them.
		If `parent` is given, then `sh` will be set to `parent.shared`. If `parent` and `sh` is null, `sh` will be set to a new context shared will be created.
		The `parent` and `sh` are then given to the clone constructor.
	**/
	public function clone(?parent:Prefab = null, ?sh: ContextShared = null, withChildren : Bool = true) : Prefab {
		if (parent != null && sh != null && parent.shared != sh)
			throw "Both parent and sh are set but shared don't match";

		if (sh == null) {
			if (parent != null) {
				sh = parent.shared;
			} else {
				sh = new hrt.prefab.ContextShared(this.shared.currentPath, true);
				#if editor
				sh.editor = shared.editor;
				sh.scene = shared.scene;
				#end
			}
		}

		var thisClass = Type.getClass(this);

		// We bypass the normal new function to avoid initializing the
		// serializable fields, because they will be initialized by the copy function
		var inst = Type.createEmptyInstance(thisClass);
		inst.postCloneInit();		// Macro function that init all the non serializable fields of a prefab
		inst.children = [];
		inst.__newInit(parent, sh);// Macro function that contains the code of the new function

		inst.copy(this);
		if (withChildren) {
			inst.children.resize(children.length);
			for (idx => child in children) {
				var cloneChild = child.clone(null, sh);

				// "parent" setter pushes into children, but we don't want that
				// as we have prealocated the array children
				@:bypassAccessor cloneChild.parent = inst;
				inst.children[idx] = cloneChild;
			}
		}

		return inst;
	}

	// Make related functions

	/**
		Create a child from this prefab. Override to filter which child should
		be created
	**/
	function makeChild(c:Prefab) : Void {
		if (shared.customMake == null) {
			c.make(shared);
		}
		else if (c.shouldBeInstanciated()) {
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
	function updateInstance(?propName : String) {
	}

	// End of make related functions

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

	/**
		Cleanup prefab specific ressources, and call dispose on it's children.
	**/
	public function dispose() {
		for (child in children) {
			child.dispose();
		}
	}

	/**
		Find the first h2d.Object in this hierarchy, in either this or it's parents
	**/
	public function findFirstLocal2d(followRefs: Bool = false) : h2d.Object {
		var o2d = findParent(Object2D, (p) -> p.local2d != null, true, followRefs);
		return o2d != null ? o2d.local2d : shared.root2d;
	}

	/**
		Find the first h3d.scene.Object in this hierarchy, in either this or it's parents
	**/
	public function findFirstLocal3d(followRefs: Bool = false) : h3d.scene.Object {
		var o3d = findParent(Object3D, (p) -> p.local3d != null, true, followRefs);
		return o3d != null ? o3d.local3d : shared.root3d;
	}

	/**
		Search the prefab tree for the prefab matching the given prefab class (and name, if specified).
		Throw an exception if not found. Uses getOpt() to return null instead.
	**/
	public function get<T:Prefab>( ?cl : Class<T>, ?name : String ) : T {
		var v = getOpt(cl, name);
		if( v == null )
			throw "Missing prefab " + (name == null ? Type.getClassName(cl) : (cl == null ? name : name+"(" + Type.getClassName(cl) + ")"));
		return v;
	}

	/**
		Simlar to get() but returns null if not found.
	**/
	public function getOpt<T:Prefab>( ?cl : Class<T>, ?name : String, ?followRefs : Bool ) : Null<T> {
		if( name == null || this.name == name ) {
			if (cl != null) {
				var cval = to(cl);
				if( cval != null ) return cval;
			}
			else {
				return cast this;
			}
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

		while( root.parent != null || (followRefs && root.shared.parentPrefab != null) ) {
			if( root.parent != null )
				root = root.parent;
			else if( followRefs )
				root = root.shared.parentPrefab;
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
	public function find<T:Prefab>(?cl: Class<T>, ?filter : T -> Bool, followRefs : Bool = false ) : Null<T> {
		var asCl = cl != null ? Std.downcast(this, cl) : cast this;
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
	public function findAll<T:Prefab>(?cl: Class<T>, ?filter : Prefab -> Bool, followRefs : Bool = false, ?arr : Array<T> ) : Array<T> {
		if( arr == null ) arr = [];
		var asCl = cl != null ? Std.downcast(this, cl) : cast this;
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
	public function findParent<T:Prefab>(?cl:Class<T> ,?filter : (p:T) -> Bool, includeSelf:Bool = false, followRefs:Bool = false) : Null<T> {
		var current = includeSelf ? this : this.parent;
		while(current != null) {
			var asCl = cl != null ? Std.downcast(current, cl) : cast current;
			if (asCl != null) {
				if (filter == null || filter(asCl))
					return asCl;
			}
			var next = current.parent;
			if (next == null && followRefs) {
				next = current.shared.parentPrefab;
			}
			current = next;
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

	/**
		Returns the absolute name path for this prefab
	**/
	public function getAbsPath(unique=false) {
		if(parent == null)
			return "";
		var path = name ?? "";
		if (path == "")
			path = hrt.prefab.Prefab.emptyNameReplacement;
		if(unique) {
			var suffix = 0;
			for(i in 0...parent.children.length) {
				var c = parent.children[i];
				if(c == this)
					break;
				else {
					var cname = c.name ?? "";
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

	/**
		Returns the default display name for this prefab
		Required outside of -D editor for the usage of hide as library
	**/
	public function getDefaultEditorName() : String {
		if(source != null) {
			var f = new haxe.io.Path(source).file;
			f = f.split(" ")[0].split("-")[0];
			return f;
		}
		return type.split(".").pop();
	}

	// Editor API

	#if editor
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
		Called by the editor to remove the object created by this prefab tree
	**/
	function editorRemoveObjects() : Void {
		for (child in children) {
			child.editorRemoveObjects();
		}
		editorRemoveInstanceObjects();
		dispose();
	}


	/**
		Called by the editor to remove the objects created by this prefab but not it's children.
	**/
	function editorRemoveInstanceObjects() : Void {
	}

	/**
		Called by the editor when a child of this object gets added, rebuild or removed.
	**/
	public function onEditorTreeChanged(child: Prefab) : TreeChangedResult {
		return Skip;
	}

	/**
		Called when the hide editor wants to edit this Prefab.
		Used to create the various editor interfaces
	**/
	public function edit(editContext : hide.prefab.EditContext) {
	}

	public function setEditor(sceneEditor: hide.comp.SceneEditor, scene: hide.comp.Scene) {
		shared.editor = sceneEditor;
		shared.scene = scene;

		setEditorChildren(sceneEditor, scene);
	}

	function setEditorChildren(sceneEditor: hide.comp.SceneEditor, scene: hide.comp.Scene) {
		for (c in children) {
			c.setEditorChildren(sceneEditor, scene);
		}
	}

	/**
		Returns a list of all the serializable fieds of the prefab.
	**/
	public final function getSerializableProps() : Array<PrefabField> {
		return getSerializablePropsForClass(Type.getClass(this));
	}

	#end

	// Internal

	function setSharedRec(newShared : ContextShared) {
		this.shared = newShared;
		for (c in children)
			c.setSharedRec(newShared);
	}

	/**
		Recursively copy this prefab and it's children into a dynamic object, containing
		all the serializable properties and the type of the object
	**/
	function serialize() : Dynamic {
		var ser = save();

		if (children.length > 0) {
			var serChildren = [];
			for (child in children) {
				serChildren.push(child.serialize());
			}
			ser.children = serChildren;
		}

		return ser;
	}

	function locateObject( path : String ) {
		if( path == null )
			return null;
		var parts = path.split(".");
		var root = shared.root3d;
		if (root == null)
			return null;
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
		Finds a prefab by folowing a dot separated path like this one : `parent.child.grandchild`.
		Returns null if the path is invalid or does not match any prefabs in the hierarchy
	**/
	function locatePrefab(path: String) : Null<Prefab> {
		if (path == null)
			return null;
		var parts = path.split(".");
		var p = this;
		while (parts.length > 0 && p != null) {
			var name = parts.shift();
			var found = null;
			for (o in p.children) {
				if (o.name == name)
				{
					found = o;
					break;
				}
			}
			p = found;
		}
		return p;
	}

	function shouldBeInstanciated() : Bool {
		if (!enabled) return false;

		#if editor
		if (inGameOnly)
			return false;
		#else
		if (!ignoreEditorOnly && editorOnly)
			return false;
		#end

		return true;
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
		var obj : Dynamic = {};
		obj.type = type;
		return this.copyToDynamic(obj);
	}

	/**
		Create a new prefab from the given `data`.
	**/
	static function createFromDynamic(data:Dynamic, parent:Prefab = null, contextShared:ContextShared = null) : Prefab {
		var type : String = data.type;

		var cl : Class<Prefab> = Unknown;

		if (type != null) {
			var classEntry = registry.get(type);
			if (classEntry != null)
				cl = classEntry.prefabClass;
		}

		var prefabInstance = Type.createInstance(cl, [parent, contextShared]);

		prefabInstance.load(data);

		var children : Array<Dynamic> = Reflect.field(data, "children");
		if (children != null) {
			for (child in children) {
				createFromDynamic(child, prefabInstance);
			}
		}

		return prefabInstance;
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

	inline static function getSerializablePropsForClass(cl : Class<Prefab>) {
		return (cl:Dynamic).getSerializablePropsStatic();
	}

	static function getClassTypeName(cl : Class<Prefab>) : String {
		return reverseRegistry.get(Type.getClassName(cl));
	}

	static function getPrefabInfoByName(name:String) : PrefabInfo {
		return registry[name];
	}

	static function getPrefabType(path: String) {
		var extension = path.split(".").pop().toLowerCase();
		return extensionRegistry.get(extension);
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

	// Static initialization trick to register this class with the given name
	// in the prefab registry. Call this in your own classes
	static var _ = Prefab.register("prefab", Prefab, "prefab");
}
