package hide.tools.migrate;

/**
	A prefab of the raw (json) data of a file, before it is loaded. The upgrade steps work on these:
	they change `data` in place, and keep the tree in sync when they add, move or rename nodes.
**/
class RawNode {
	public var data : Dynamic;
	public var parent : RawNode;
	public var children : Array<RawNode> = [];
	/** The name the prefab gets once loaded (curves: `.` becomes `:`) **/
	public var name : String;
	public var type : String;
	public var cls : Class<hrt.prefab.Prefab>;
	public var isCurve : Bool;
	/** The child indices of the node from the root, in the data as it was read. Null for a node made by the upgrade. **/
	public var origin : Array<Int>;

	public function new() {}

	public static function build( data : Dynamic, parent : RawNode, ?origin : Array<Int> ) : RawNode {
		var n = new RawNode();
		n.data = data;
		n.parent = parent;
		n.origin = origin;
		n.type = get(data, "type");
		n.cls = classOf(n.type);
		n.isCurve = n.cls != null && (hrt.prefab.Prefab.isOfType(n.cls, hrt.prefab.Curve) || hrt.prefab.Prefab.isOfType(n.cls, hrt.prefab.fx.Curve));
		n.name = loadedName(n);
		var children : Array<Dynamic> = get(data, "children");
		if( children != null )
			for( c in children )
				if( c != null )
					n.children.push(build(c, n, origin == null ? null : origin.concat([n.children.length])));
		return n;
	}

	/** Mirrors `Curve.load` (game build): a `.` in the name of a curve becomes `:`. **/
	static function loadedName( n : RawNode ) : String {
		var name : String = get(n.data, "name") ?? "";
		return n.isCurve ? StringTools.replace(name, ".", ":") : name;
	}

	public function rename( name : String ) {
		data.name = name;
		this.name = isCurve ? StringTools.replace(name, ".", ":") : name;
	}

	public static function classOf( type : String ) : Class<hrt.prefab.Prefab> {
		if( type == null ) return null;
		var info = @:privateAccess hrt.prefab.Prefab.getPrefabInfoByName(type);
		return info?.prefabClass;
	}

	/** A field of raw data **/
	public static inline function get( d : Dynamic, f : String ) : Dynamic {
		return Reflect.field(d, f);
	}

	public function isA( cl : Class<hrt.prefab.Prefab> ) {
		return cls != null && hrt.prefab.Prefab.isOfType(cls, cl);
	}

	public function enabled() {
		return get(data, "enabled") != false;
	}

	/** Like `Prefab.getUniqueName`: `name-N` for the Nth sibling of the same name. **/
	public function uniqueName() {
		if( parent == null )
			return "";
		var n = 0;
		for( c in parent.children ) {
			if( c == this ) break;
			if( c.name == name ) n++;
		}
		return n > 0 ? name + "-" + n : name;
	}

	/** The unique path from the root, for messages **/
	public function path() {
		var parts = [];
		var p = this;
		while( p != null && p.parent != null ) {
			parts.unshift(p.uniqueName());
			p = p.parent;
		}
		return parts.join(".");
	}

	public function curveChildren() {
		return [for( c in children ) if( c.isCurve ) c];
	}

	/** Appends a child (data and node) **/
	public function addChild( d : Dynamic ) : RawNode {
		var arr : Array<Dynamic> = get(data, "children");
		if( arr == null ) {
			arr = [];
			setField(data, "children", arr);
		}
		arr.push(d);
		var n = build(d, this);
		children.push(n);
		return n;
	}

	/** Rebuilds the nodes of the children from the data (the data of the node was replaced) **/
	public function rebuildChildren() {
		var rebuilt = build(data, parent);
		children = rebuilt.children;
		for( c in children ) c.parent = this;
	}

	/**
		Sets a field of an object, before `children` when it is a new one: the order a prefab saves
		its fields in (`Prefab.serialize` adds the children last).
	**/
	public static function setField( o : Dynamic, f : String, v : Dynamic ) {
		if( Reflect.hasField(o, f) || !Reflect.hasField(o, "children") ) {
			Reflect.setField(o, f, v);
			return;
		}
		var fields = Reflect.fields(o);
		var values = [for( k in fields ) Reflect.field(o, k)];
		for( k in fields ) Reflect.deleteField(o, k);
		for( i => k in fields ) {
			if( k == "children" ) Reflect.setField(o, f, v);
			Reflect.setField(o, k, values[i]);
		}
	}

	/** Replaces the fields of `o` by the ones of `by`, in their order (`o` keeps its identity) **/
	public static function replaceFields( o : Dynamic, by : Dynamic ) {
		for( k in Reflect.fields(o) ) Reflect.deleteField(o, k);
		for( k in Reflect.fields(by) ) Reflect.setField(o, k, Reflect.field(by, k));
	}
}
