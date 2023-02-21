package hrt.prefab2;

using hrt.prefab2.Object3D;
using hrt.prefab2.Object2D;



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

class ContextShared {
	public function new() {

	}

	public var source : String = null;
	public var cache : h3d.prim.ModelCache = new h3d.prim.ModelCache();
	public var isPrototype = true;
	public var originalContext : InstanciateContext = null;
	public var currentPath : String = "";

#if editor
	public var scene : hide.comp2.Scene = null;
#end
}

class InstanciateContext {
	public function new(local2d: h2d.Object, local3d: h3d.scene.Object) {
		this.local2d = local2d;
		this.local3d = local3d;
	}

	public var local2d : h2d.Object = null;
	public var local3d : h3d.scene.Object = null;
	public var forceInstanciate : Bool = false; /** Force the instanciation of the prefab even if it's a template **/
}

typedef PrefabInfo = {prefabClass : Class<Prefab> #if editor, inf : hide.prefab2.HideProps #end};

@:keepSub
@:autoBuild(hrt.prefab2.Macros.buildPrefab())
@:build(hrt.prefab2.Macros.buildPrefab())
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
		A storage for some extra properties
	**/
	@:s public var props : Any = null;

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
		The associated source file (an image, a 3D model, etc.) if the prefab type needs it.
	**/
	@:s public var source : String;

	/**
		The parent of the prefab in the tree view
	**/
	public var children : Array<Prefab> = [];

	/**
		The parent of the prefab in the tree view
	**/
	public var parent(default, set) : Prefab = null;

	/**Cache of values**/
	public var shared : ContextShared = null;

	// Public API

	public function new(?parent:Prefab = null) {
		this.parent = parent;
	}

	// Accessors
	function get_type() {
		var thisClass = Type.getClass(this);
		return getClassTypeName(thisClass);
	}

	function set_parent(p) {
		if( parent != null )
			parent.children.remove(this);
		parent = p;
		if( parent != null ) {
			shared = parent.shared;
			parent.children.push(this);
		}
		return p;
	}

	public function getSource() : String {
		return null;
	}

	// Lifetime

	// Like make but in-place
	public function instanciate(params: InstanciateContext) {
		if (!params.forceInstanciate && (shared.isPrototype))
			throw "Can't instanciate a template prefab unless params.forceInstanciate is true.";
		shared.originalContext = params;
		makeInstanceRec(params);

		refresh();
	}

	// Remove this prefab and their object from the prefab and scene hierarchy
	public final function remove() {
		if (parent != null) {
			parent = null;
		}


		function detachRec(prefab:Prefab, newRoot: Prefab, removedClasses: Array<Class<Prefab>>) : Void {
			var removed = detach(newRoot, removedClasses);
			if (removed != null)
				removedClasses.push(removed);
			for (c in prefab.children) {
				detachRec(c,newRoot, removedClasses);
			}
			if (removed!= null)
				removedClasses.remove(removed);
		}

		detachRec(this, this, []);
	}

	public static function createFromDynamic(data:Dynamic, parent:Prefab = null) : Prefab {
		var type : String = data.type;

		var cl : Class<Prefab> = Unknown;
		if (type != null) {
			var classEntry = registry.get(type);
			if (classEntry != null)
				cl = classEntry.prefabClass;
		}

		// Converting (old) prefabs roots to Object3D automatically
		if (parent == null && cl == Prefab)
			cl = Object3D;

		var prefabInstance = Type.createInstance(cl, [parent]);

		prefabInstance.shared = new ContextShared();
		prefabInstance.load(data);

		var children = Std.downcast(Reflect.field(data, "children"), Array);
		if (children != null) {
			for (child in children) {
				createFromDynamic(child, prefabInstance);
			}
		}

		return prefabInstance;
	}

	public static function createFromPath(path: String, parent: Prefab = null) : Prefab {
		return hxd.res.Loader.currentInstance.load(path).to(hrt.prefab2.Resource).load();
	}

	// Hierarchical Helpers

	public function findFirstLocal2d() : h2d.Object {
		var l2d = findParent((p) -> p.getLocal2d(), true);
		return l2d != null ? l2d : shared.originalContext.local2d;
	}

	// Find the first local3d object, either in this object or it's parents
	public function findFirstLocal3d() : h3d.scene.Object {
		var l3d = findParent((p) -> p.getLocal3d(), true);
		return l3d != null ? l3d : shared.originalContext.local3d;
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

	public static function isOfType( original : Class<Prefab>, parent : Class<Prefab> ) {
		var c : Class<Dynamic> = original;
		while( c != null ) {
			if( c == parent ) return true;
			c = Type.getSuperClass(c);
		}
		return false;
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
	public function getRoot() : Prefab {
		var root = this;

		while (root.parent != null) {
			root = root.parent;
		}
		return root;
	}

	/**
		Returns the first parent in the tree matching the specified class or null if not found.
	**/
	public function getParent<T:Prefab>( c : Class<T> ) : Null<T> {
		return findParent(p -> p.to(c));
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
		Find several prefabs in the tree by calling `f` on each and returning all the non-null values returned.
	**/
	public function findAll<T>( f : Prefab -> Null<T>, ?followRefs : Bool, ?arr : Array<T> ) : Array<T> {
		if( arr == null ) arr = [];
		var v = f(this);
		if( v != null )
			arr.push(v);
		if (followRefs) {
			var ref = to(Reference);
			if (ref != null && ref.refInstance != null) {
				ref.refInstance.findAll(f, followRefs, arr);
			}
		}
		for( o in children )
			o.findAll(f,followRefs,arr);
		return arr;
	}

	/**
		Apply the filter function to this object, returning the result of filter if it's not null.
		If the filters returns null, it's then applied to the parent of this prefab, and this recursively.
	**/
	inline public function findParent<T>(filter : (p:Prefab) -> Null<T>, includeSelf:Bool = false) : Null<T> {
		var current = includeSelf ? this : this.parent;
		var val = null;
		while(current != null && val == null) {
			val = filter(current);
			current = current.parent;
		}
		return val;
	}

	inline public function filterParents<T>(filter : (p:Prefab) -> Null<T>, includeSelf: Bool = false, ?array: Array<T>) : Array<T> {
		if (array == null)
			array = [];

		var current = includeSelf ? this : this.parent;
		while(current != null) {
			var val = filter(current);
			if (val != null)
				array.push(val);
			current = current.parent;
		}
		return array;
	}

	/**
		Iterate over children prefab
	**/
	public inline function iterator() : Iterator<Prefab> {
		return children.iterator();
	}

	// (Un)Serialization

	/**
		Recursively copy this prefab and it's children into a dynamic object, containing
		all the serializable properties and the type of the object
	**/
	public function serializeToDynamic() : Dynamic {
		var thisClass = Type.getClass(this);
		var typeName = getClassTypeName(thisClass);
		var dyn : Dynamic = {
			type: typeName,
		};

		save(dyn);

		if (children.length > 0) {
			var serChildren = [];
			for (child in children) {
				serChildren.push(child.serializeToDynamic());
			}
			dyn.children = serChildren;
		}

		return dyn;
	}

	/**
		Copy all the fields from this prefab to the target prefab, recursively
	**/
	public static function copy(source:Prefab, dest:Prefab, useProperty:Bool, copyNull:Bool)
	{
		copyShallow(source, dest, useProperty, copyNull, false, source.getSerializableProps());
		for (idx in 0...source.children.length) {
			copy(source.children[idx], dest.children[idx], useProperty, copyNull);
		}
	}

	// Helpers function for meta
	public final function getSerializableProps() : Array<PrefabField> {
		return getSerializablePropsForClass(Type.getClass(this));
	}

	inline public static function getSerializablePropsForClass(cl : Class<Prefab>) {
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

	/**
		Register the given prefab class with the given typeName in the prefab regsitry.
		This is necessary for the serialisation system.
		Call it by placing this in you prefab class :
		```
		public static var _ = Prefab.register("myPrefabName", myPrefabClassName);
		```
	**/
	public static function register(typeName : String, prefabClass: Class<hrt.prefab2.Prefab>) {
		var info : hide.prefab2.HideProps = cast Type.createEmptyInstance(prefabClass).getHideProps();

		reverseRegistry.set(Type.getClassName(prefabClass), typeName);
		registry.set(typeName, {prefabClass: prefabClass #if editor, inf : info #end});
		return true;
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
		Returns the default display name for this prefab
	**/
	public function getDefaultName() : String {
		if(shared.source != null) {
			var f = new haxe.io.Path(shared.source).file;
			f = f.split(" ")[0].split("-")[0];
			return f;
		}
		return type.split(".").pop();
	}

	public function locateObject( path : String ) {
		if( path == null )
			return null;
		var parts = path.split(".");
		var root = getRoot().getLocal3d();
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

	/**
		Misc
	**/

	public final function toString() : String{
		return 'prefab:{type: $type, name: $name}';
	}

	public function dumpInfo() : String {
		return haxe.Json.stringify(serializeToDynamic(), null, "\t");
	}

	/*
		overridable API
	*/

	/**
		Override this function if you want to controll how the childrens are
		made
	**/
	function makeInstanceRec(params: InstanciateContext) : Void {
		if (!enabled) return;

		var old2d = params.local2d;
		var old3d = params.local3d;

		makeInstance(params);

		var new2d = this.getLocal2d();
		if (new2d != null)
			params.local2d = new2d;
		var new3d = this.getLocal3d();
		if (new3d != null)
			params.local3d = new3d;
		for (c in children) {
			c.makeInstanceRec(params);
		}

		params.local2d = old2d;
		params.local3d = old3d;

		postChildrenMakeInstance(params);

		params.local2d = old2d;
		params.local3d = old3d;
	}

	public function loadDir(p : String, ?dir : String ) : Array<hxd.res.Any> {
		var datPath = new haxe.io.Path(shared.currentPath);
		datPath.ext = "dat";
		var path = datPath.toString() + "/" + p;
		if(dir != null) path += "/" + dir;
		return try hxd.res.Loader.currentInstance.dir(path) catch( e : hxd.res.NotFound ) null;
	}

	function loadModel( path : String ) {
		return shared.cache.loadModel(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	function loadAnimation( path : String ) {
		return shared.cache.loadAnimation(hxd.res.Loader.currentInstance.load(path).toModel());
	}

	function loadTexture( path : String, async : Bool = false ) {
		return shared.cache.loadTexture(null, path, async);
	}

	public function getPrefabDatPath(file : String, ext : String, prefab : String ) {
		var datPath = new haxe.io.Path(shared.currentPath);
		datPath.ext = "dat";
		var path = new haxe.io.Path(datPath.toString() + "/" + prefab + "/" + file);
		path.ext = ext;
		return path.toString();
	}

	function loadPrefabDat(file : String, ext : String, prefab : String) : hxd.res.Any {
		return try hxd.res.Loader.currentInstance.load(getPrefabDatPath(file,ext,prefab)) catch( e : hxd.res.NotFound ) null;
	}

	#if editor

	function savePrefabDat(file : String, ext:String, p : String, bytes : haxe.io.Bytes ){
		var path = new haxe.io.Path(shared.currentPath);
		path.ext = "dat";
		var datDir = path.toString();
		var instanceDir = datDir + "/" + p;

		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(datDir)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(datDir));
		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(instanceDir)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(instanceDir));

		var path = new haxe.io.Path("");
		path.dir = instanceDir;
		path.file = file;
		path.ext = ext;
		var file = hide.Ide.inst.getPath(path.toString());

		if( bytes == null ){
			try sys.FileSystem.deleteFile(file) catch( e : Dynamic ) {};
			var p = hide.Ide.inst.getPath(instanceDir);
			if(sys.FileSystem.isDirectory(p)){
				var dir = sys.FileSystem.readDirectory(p);
				if(dir.length == 0) sys.FileSystem.deleteDirectory(p);
			}
			var p = hide.Ide.inst.getPath(datDir);
			if(sys.FileSystem.isDirectory(p)){
				var dir = sys.FileSystem.readDirectory(p);
				if(dir.length == 0) sys.FileSystem.deleteDirectory(p);
			}
			return;
		}else{
			sys.io.File.saveBytes(file, bytes);
		}
	}

	function saveTexture(file:String, bytes:haxe.io.Bytes, dir:String, ext:String) {
		var path = new haxe.io.Path("");
		path.dir = dir + "/";
		path.file = file;
		path.ext = ext;

		if(!sys.FileSystem.isDirectory( hide.Ide.inst.getPath(dir)))
			sys.FileSystem.createDirectory( hide.Ide.inst.getPath(dir));

		var file = hide.Ide.inst.getPath(path.toString());
		sys.io.File.saveBytes(file, bytes);
	}
	#end

	/**
		Override this function to create runtime objects from this prefab
	**/
	function makeInstance(ctx: InstanciateContext) : Void {

	}

	/**
		Called after makeInstance (and by extension postChildrenMakeInstance) has been called on all the children
	**/
	function postChildrenMakeInstance(ctx: InstanciateContext) : Void {
	}

	/**
		Allows to customize how an instance gets updated when a property name changes.
		You can also call updateInstance(ctx) in order to force whole instance synchronization against current prefab data.
	**/
	public function updateInstance(?propName : String ) {
	}

	/**
		Called by remove on all the prefabs in the tree.
		This function should remove objects created in makeInstance if they were
		attached to objects that are no longer present in the tree.
		You can use removedClasses to keep track of classes that already detached themselves
		(i.e logically only the first Object3D in a branch should remove itself)
	**/
	function detach(newRoot: Prefab, removedClasses: Array<Class<Prefab>>) : Class<Prefab> {
		return null;
	}

	/**
		Call all the setters of this object and its children
	**/
	public function refresh() {
		for (field in getSerializableProps()) {
			if (field.hasSetter) {
				Reflect.setProperty(this, field.name, Reflect.getProperty(this, field.name));
			}
		}
		for (child in children) {
			child.refresh();
		}
	}

	/*
		Internal functionalities
	*/

	/**
		Call the autogenerated make(?root: Prefab = null, ?o2d: h2d.Object = null, ?o3d: h3d.scene.Object = null) function instead which is properly typed
		for each prefab using macro
	**/
	@:noCompletion
	final function makeInternal(?root: Prefab = null, ?o2d: h2d.Object = null, ?o3d: h3d.scene.Object = null) : Prefab {
		var newInstance = copyDefault(root);
		newInstance.shared = new ContextShared();
		newInstance.shared.isPrototype = false;

		o2d = o2d != null ? o2d : (root != null ? root.findFirstLocal2d() : null);
		o3d = o3d != null ? o3d : (root != null ? root.findFirstLocal3d() : null);
		var params = new InstanciateContext(o2d, o3d);

		newInstance.instanciate(params);

		return newInstance;
	};

	/**
		Create a copy of this prefab and it's childrens, whitout initializing their fields
	**/
	final function copyDefault(?parent:Prefab = null) : Prefab {
		var thisClass = Type.getClass(this);
		var inst = Type.createInstance(thisClass, [parent]);
		copyShallow(this, inst, false, true, true, getSerializableProps());
		for (child in children) {
			child.copyDefault(inst);
		}
		return inst;
	}

	/**
		Only copy a prefab serializable properties without it's children
	**/
	static function copyShallow(source:Dynamic, dest:Dynamic, useProperty:Bool, copyNull:Bool, copyDefault: Bool, props:Array<PrefabField>) {
		var set = useProperty ? Reflect.setProperty : Reflect.setField;

		for (prop in props) {
			var v : Dynamic = Reflect.getProperty(source, prop.name);
			var shouldCopy = true;
			shouldCopy = shouldCopy && (v != null || copyNull);
			shouldCopy = shouldCopy && (copyDefault || useProperty || v != prop.defaultValue);
			//shouldCopy &= (copyDefault || ) 
			if (shouldCopy) {
				set(dest, prop.name, copyValue(v));
			}
		}
	}

	static function copyValue(v:Dynamic) : Dynamic {
		switch (Type.typeof(v)) {
			case TClass(c):
				trace(Type.getClassName(c));
				switch(c) {
					case cast Array:
						var v:Array<Dynamic> = v;
						return v.copy();
					case cast String:
						var v:String = v;
						return v;
					default:
						// TODO : oh no
						return haxe.Json.parse(haxe.Json.stringify(v));
				}
			default:
				return v;
		}
	}

	/** Copy all the properties in data to this prefab object. This is not recursive**/
	public function load(data : Dynamic) : Void {
		copyShallow(data, this, false, false, false, getSerializableProps());
	}

	/** Save all the properties to the given dynamic object. This is not recursive. Returns the updated dynamic object.
		If to is null, a new dynamic object is created automatically and returned by the
	**/
	public function save(to: Dynamic) : Dynamic {
		copyShallow(this, to, false, false, false, getSerializableProps());
		return to;
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

	static var cache : Map<String, Prefab> = new Map();

#if editor
	/*
		Editor API
	*/

	/**
		Allows to customize how the prefab object is displayed / handled within Hide
	**/
	public function getHideProps() : hide.prefab2.HideProps {
		return { icon : "question-circle", name : "Unknown" };
	}

	public function makeInteractive() : hxd.SceneEvents.Interactive {
		return null;
	}

	/**
		Allows to customize how the prefab instance changes when selected/unselected within Hide.
		Selection of descendants is skipped if false is returned.
	**/
	public function setSelected(b : Bool ) {
		return true;
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
		Called when the hide editor wants to edit this Prefab.
		Used to create the various editor interfaces
	**/
	public function edit(editContext : hide.prefab2.EditContext) {

	}
#end

	// Static initialization trick to register this class with the given name
	// in the prefab registry. Call this in your own classes 
	public static var _ = Prefab.register("prefab", Prefab);

	/*inline public function findParent<T:Prefab,R>( cl : Class<T>, ?filter : (p:T) -> Null<R>) : Null<R> {
		var current = this;
		var val = null;

		while(current != null && val == null) {
			var c = Std.downcast(current, cl);
			if (c != null) {
				if (filter != null)
					val = filter(c);
				else
					val = c;
			}
			current = current.parent;
		}

		return val;
	}*/

}