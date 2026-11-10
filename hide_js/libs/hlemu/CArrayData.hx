package hlemu;

/** the data of a CArray (its own module : with Haxe 5 preview.1, the type of a macro is resolved by its path) **/
@:noCompletion class CArrayData {
	public var cl : Dynamic;
	public var stride : Int;
	public var count : Int;
	public var view : js.lib.DataView;
	/** native address, same name as the structs field (see Struct.addr) **/
	public var __a : Float;
	public var items : Array<Dynamic>;
	public function new() {
	}
	public function __sync() {
		if( !cl.__NEEDSYNC ) return;
		for( it in items )
			if( it != null ) it.__sync();
	}
}
